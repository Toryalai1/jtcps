#include <cstdint>
#include <cstdio>
#include "cps2crypt.h"

using namespace std;

int init_cps2crypt(char *m_key, MAME_keys& keys)
{
	unsigned short decoded[10] = { 0 };
	int first=159;
	bool found=false;
	for (int b = 0; b < 10 * 16; b++)
	{
		int bit = (317 - b) % 160;
		if ((m_key[bit / 8] >> ((bit ^ 7) % 8)) & 1)
		{
			decoded[b / 16] |= (0x8000 >> (b % 16));
		}
	}
	/*
	puts("MAME decoding:");
	for( int k=9; k>=0; k-- ) {
		for( int j=1; j>=0; j-- ) {
			int i = (decoded[k]>>(8*j))&0xff;
			printf("%02X",i);
			if( !found ) {
				for( int x=0x80; x>=1; x>>=1 ) {
					if( i&x ) {
						found =true;
						break;
					} else {
						first--;
					}
				}
			}
		}
	}
	//puts("");
	*/

	keys.key[0] = ((uint32_t)decoded[0] << 16) | decoded[1];
	keys.key[1] = ((uint32_t)decoded[2] << 16) | decoded[3];

	// decoded[4] == watchdog instruction third word
	// decoded[5] == watchdog instruction second word
	// decoded[6] == watchdog instruction first word
	// decoded[7] == 0x4000 (bits 8 to 23 of CPS2 object output address)
	// decoded[8] == 0x0900

	uint32_t lower;
	if (decoded[9] == 0xffff)
	{
		// On a dead board, the only encrypted range is actually FF0000-FFFFFF.
		// It doesn't start from 0, and it's the upper half of a 128kB bank.
		keys.upper = 0xffffff;
		lower = 0xff0000;
	}
	else
	{
		keys.upper = (((~decoded[9] & 0x3ff) << 14) | 0x3fff) + 1;
		lower = 0;
	}

	// we have a proper key so use it to decrypt
	// cps2_decrypt(machine(), (uint16_t *)memregion("maincpu")->base(), m_decrypted_opcodes, memregion("maincpu")->bytes(), key, lower / 2, upper / 2);
	return first;
}


/******************************************************************************/


uint8_t fn(uint8_t in, const struct optimised_sbox *sboxes, uint32_t key)
{
	const struct optimised_sbox *sbox1 = &sboxes[0];
	const struct optimised_sbox *sbox2 = &sboxes[1];
	const struct optimised_sbox *sbox3 = &sboxes[2];
	const struct optimised_sbox *sbox4 = &sboxes[3];

	return
		sbox1->output[sbox1->input_lookup[in] ^ ((key >>  0) & 0x3f)] |
		sbox2->output[sbox2->input_lookup[in] ^ ((key >>  6) & 0x3f)] |
		sbox3->output[sbox3->input_lookup[in] ^ ((key >> 12) & 0x3f)] |
		sbox4->output[sbox4->input_lookup[in] ^ ((key >> 18) & 0x3f)];
}



// srckey is the 64-bit master key (2x32 bits)
// dstkey will contain the 96-bit key for the 1st FN (4x24 bits)
void expand_1st_key(uint32_t *dstkey, const uint32_t *srckey)
{
	static const int bits[96] =
	{
		33, 58, 49, 36,  0, 31,
		22, 30,  3, 16,  5, 53,
		10, 41, 23, 19, 27, 39,
		43,  6, 34, 12, 61, 21,
		48, 13, 32, 35,  6, 42,
		43, 14, 21, 41, 52, 25,
		18, 47, 46, 37, 57, 53,
		20,  8, 55, 54, 59, 60,
		27, 33, 35, 18,  8, 15,
		63,  1, 50, 44, 16, 46,
			5,  4, 45, 51, 38, 25,
		13, 11, 62, 29, 48,  2,
		59, 61, 62, 56, 51, 57,
		54,  9, 24, 63, 22,  7,
		26, 42, 45, 40, 23, 14,
			2, 31, 52, 28, 44, 17,
	};
	int i;

	dstkey[0] = 0;
	dstkey[1] = 0;
	dstkey[2] = 0;
	dstkey[3] = 0;

	for (i = 0; i < 96; ++i)
		dstkey[i / 24] |= BIT(srckey[bits[i] / 32], bits[i] % 32) << (i % 24);
}


// srckey is the 64-bit master key (2x32 bits) XORed with the subkey
// dstkey will contain the 96-bit key for the 2nd FN (4x24 bits)
void expand_2nd_key(uint32_t *dstkey, const uint32_t *srckey)
{
	static const int bits[96] =
	{
		34,  9, 32, 24, 44, 54,
		38, 61, 47, 13, 28,  7,
		29, 58, 18,  1, 20, 60,
		15,  6, 11, 43, 39, 19,
		63, 23, 16, 62, 54, 40,
		31,  3, 56, 61, 17, 25,
		47, 38, 55, 57,  5,  4,
		15, 42, 22,  7,  2, 19,
		46, 37, 29, 39, 12, 30,
		49, 57, 31, 41, 26, 27,
		24, 36, 11, 63, 33, 16,
		56, 62, 48, 60, 59, 32,
		12, 30, 53, 48, 10,  0,
		50, 35,  3, 59, 14, 49,
		51, 45, 44,  2, 21, 33,
		55, 52, 23, 28,  8, 26,
	};
	int i;

	dstkey[0] = 0;
	dstkey[1] = 0;
	dstkey[2] = 0;
	dstkey[3] = 0;

	for (i = 0; i < 96; ++i)
		dstkey[i / 24] |= BIT(srckey[bits[i] / 32], bits[i] % 32) << (i % 24);
}



// seed is the 16-bit seed generated by the first FN
// subkey will contain the 64-bit key to be XORed with the master key
// for the 2nd FN (2x32 bits)
void expand_subkey(uint32_t* subkey, uint16_t seed)
{
	// Note that each row of the table is a permutation of the seed bits.
	static const int bits[64] =
	{
			5, 10, 14,  9,  4,  0, 15,  6,  1,  8,  3,  2, 12,  7, 13, 11,
			5, 12,  7,  2, 13, 11,  9, 14,  4,  1,  6, 10,  8,  0, 15,  3,
			4, 10,  2,  0,  6,  9, 12,  1, 11,  7, 15,  8, 13,  5, 14,  3,
		14, 11, 12,  7,  4,  5,  2, 10,  1, 15,  0,  9,  8,  6, 13,  3,
	};
	int i;

	subkey[0] = 0;
	subkey[1] = 0;

	for (i = 0; i < 64; ++i)
		subkey[i / 32] |= BIT(seed, bits[i]) << (i % 32);
}



uint16_t feistel(uint16_t val, const int *bitsA, const int *bitsB,
		const struct optimised_sbox* boxes1, const struct optimised_sbox* boxes2, const struct optimised_sbox* boxes3, const struct optimised_sbox* boxes4,
		uint32_t key1, uint32_t key2, uint32_t key3, uint32_t key4)
{
	uint8_t l = bitswap<8>(val, bitsB[7],bitsB[6],bitsB[5],bitsB[4],bitsB[3],bitsB[2],bitsB[1],bitsB[0]);
	uint8_t r = bitswap<8>(val, bitsA[7],bitsA[6],bitsA[5],bitsA[4],bitsA[3],bitsA[2],bitsA[1],bitsA[0]);

	l ^= fn(r, boxes1, key1);
	r ^= fn(l, boxes2, key2);
	l ^= fn(r, boxes3, key3);
	r ^= fn(l, boxes4, key4);

	return
		(BIT(l, 0) << bitsA[0]) |
		(BIT(l, 1) << bitsA[1]) |
		(BIT(l, 2) << bitsA[2]) |
		(BIT(l, 3) << bitsA[3]) |
		(BIT(l, 4) << bitsA[4]) |
		(BIT(l, 5) << bitsA[5]) |
		(BIT(l, 6) << bitsA[6]) |
		(BIT(l, 7) << bitsA[7]) |
		(BIT(r, 0) << bitsB[0]) |
		(BIT(r, 1) << bitsB[1]) |
		(BIT(r, 2) << bitsB[2]) |
		(BIT(r, 3) << bitsB[3]) |
		(BIT(r, 4) << bitsB[4]) |
		(BIT(r, 5) << bitsB[5]) |
		(BIT(r, 6) << bitsB[6]) |
		(BIT(r, 7) << bitsB[7]);
}



int extract_inputs(uint32_t val, const int *inputs)
{
	int i;
	int res = 0;

	for (i = 0; i < 6; ++i)
	{
		if (inputs[i] != -1)
			res |= BIT(val, inputs[i]) << i;
	}

	return res;
}



void optimise_sboxes(struct optimised_sbox* out, const struct sbox* in)
{
	int box;

	for (box = 0; box < 4; ++box)
	{
		int i;

		// precalculate the input lookup
		for (i = 0; i < 256; ++i)
		{
			out[box].input_lookup[i] = extract_inputs(i, in[box].inputs);
		}

		// precalculate the output masks
		for (i = 0; i < 64; ++i)
		{
			int o = in[box].table[i];

			out[box].output[i] = 0;
			if (o & 1)
				out[box].output[i] |= 1 << in[box].outputs[0];
			if (o & 2)
				out[box].output[i] |= 1 << in[box].outputs[1];
		}
	}
}

void cps2_decrypt( uint16_t *rom, uint16_t *dec, int length, const uint32_t *master_key, uint32_t lower_limit, uint32_t upper_limit)
{
	int i;
	uint32_t key1[4];
	struct optimised_sbox sboxes1[4*4];
	struct optimised_sbox sboxes2[4*4];

	optimise_sboxes(&sboxes1[0*4], fn1_r1_boxes);
	optimise_sboxes(&sboxes1[1*4], fn1_r2_boxes);
	optimise_sboxes(&sboxes1[2*4], fn1_r3_boxes);
	optimise_sboxes(&sboxes1[3*4], fn1_r4_boxes);
	optimise_sboxes(&sboxes2[0*4], fn2_r1_boxes);
	optimise_sboxes(&sboxes2[1*4], fn2_r2_boxes);
	optimise_sboxes(&sboxes2[2*4], fn2_r3_boxes);
	optimise_sboxes(&sboxes2[3*4], fn2_r4_boxes);


	// expand master key to 1st FN 96-bit key
	expand_1st_key(key1, master_key);

	// add extra bits for s-boxes with less than 6 inputs
	key1[0] ^= BIT(key1[0], 1) <<  4;
	key1[0] ^= BIT(key1[0], 2) <<  5;
	key1[0] ^= BIT(key1[0], 8) << 11;
	key1[1] ^= BIT(key1[1], 0) <<  5;
	key1[1] ^= BIT(key1[1], 8) << 11;
	key1[2] ^= BIT(key1[2], 1) <<  5;
	key1[2] ^= BIT(key1[2], 8) << 11;

	for (i = 0; i < 0x10000; ++i)
	{
		int a;
		uint16_t seed;
		uint32_t subkey[2];
		uint32_t key2[4];

		// pass the address through FN1
		seed = feistel(i, fn1_groupA, fn1_groupB,
				&sboxes1[0*4], &sboxes1[1*4], &sboxes1[2*4], &sboxes1[3*4],
				key1[0], key1[1], key1[2], key1[3]);


		// expand the result to 64-bit
		expand_subkey(subkey, seed);

		// XOR with the master key
		subkey[0] ^= master_key[0];
		subkey[1] ^= master_key[1];

		// expand key to 2nd FN 96-bit key
		expand_2nd_key(key2, subkey);

		// add extra bits for s-boxes with less than 6 inputs
		key2[0] ^= BIT(key2[0], 0) <<  5;
		key2[0] ^= BIT(key2[0], 6) << 11;
		key2[1] ^= BIT(key2[1], 0) <<  5;
		key2[1] ^= BIT(key2[1], 1) <<  4;
		key2[2] ^= BIT(key2[2], 2) <<  5;
		key2[2] ^= BIT(key2[2], 3) <<  4;
		key2[2] ^= BIT(key2[2], 7) << 11;
		key2[3] ^= BIT(key2[3], 1) <<  5;


		// decrypt the opcodes
		for (a = i; a < length/2; a += 0x10000)
		{
			if (a >= lower_limit && a <= upper_limit)
			{
				dec[a] = feistel(rom[a], fn2_groupA, fn2_groupB,
					&sboxes2[0 * 4], &sboxes2[1 * 4], &sboxes2[2 * 4], &sboxes2[3 * 4],
					key2[0], key2[1], key2[2], key2[3]);
			}
			else
			{
				dec[a] = rom[a];
			}
		}
	}
}





