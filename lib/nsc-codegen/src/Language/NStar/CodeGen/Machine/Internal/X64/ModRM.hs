{-# LANGUAGE BinaryLiterals #-}

module Language.NStar.CodeGen.Machine.Internal.X64.ModRM
( -- * Calculating the ModR/M byte
  -- $modrm

  -- * ModR/M constructors
modRM, modRMRegOffsetIntoReg, modRMRegAsOffsetIntoReg, modRMRegIntoRegAsOffset, modRMRegToReg
) where

import Data.Word (Word8)
import Data.Bits (shiftL, (.&.), (.|.))
import Language.NStar.CodeGen.Machine.Internal.Intermediate (InterOpcode(..))
import Language.NStar.CodeGen.Machine.Internal.X64.RegisterEncoding (registerNumber)
import Language.NStar.Syntax.Core (Register)

{- $modrm

+------------------------------------+------+------+------+------+------+------+------+------+
|               r8 (/r)              | AL   | CL   | DL   | BL   | AH   | CH   | DH   | BH   |
+------------------------------------+------+------+------+------+------+------+------+------+
|              r16 (/r)              | AX   | CX   | DX   | BX   | SP   | BP   | SI   | DI   |
+------------------------------------+------+------+------+------+------+------+------+------+
|              r32 (/r)              | EAX  | ECX  | EDX  | EBX  | ESP  | EBP  | ESI  | EDI  |
+------------------------------------+------+------+------+------+------+------+------+------+
|               r64 (/)              | RAX  | RCX  | RDX  | RBX  | RSP  | RBP  | RSI  | RDI  |
+------------------------------------+------+------+------+------+------+------+------+------+
|               mm (/r)              | MM0  | MM1  | MM2  | MM3  | MM4  | MM5  | MM6  | MM7  |
+------------------------------------+------+------+------+------+------+------+------+------+
|              xmm (/r)              | XMM0 | XMM1 | XMM2 | XMM3 | XMM4 | XMM5 | XMM6 | XMM7 |
+------------------------------------+------+------+------+------+------+------+------+------+
|    (In decimal) /digit (Opcode)    |   0  |   1  |   2  |   3  |   4  |   5  |   6  |   7  |
+------------------------------------+------+------+------+------+------+------+------+------+
|          (In binary) REG =         |  000 |  001 |  010 |  011 |  100 |  101 |  110 |  111 |
+------------------------+-----+-----+------+------+------+------+------+------+------+------+
|    Effective Address   | Mod | R/M |         Value of ModR/M Byte (in Hexadecimal)         |
+========================+=====+=====+======+======+======+======+======+======+======+======+
|          [EAX]         |  00 | 000 |  00  |  08  |  10  |  18  |  20  |  28  |  30  |  38  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|          [ECX]         |     | 001 |  01  |  09  |  11  |  19  |  21  |  29  |  31  |  39  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|          [EDX]         |     | 010 |  02  |  0A  |  12  |  1A  |  22  |  2A  |  32  |  3A  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|          [EBX]         |     | 011 |  03  |  0B  |  13  |  1B  |  23  |  2B  |  33  |  3B  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|        [--][--]        |     | 100 |  04  |  0C  |  14  |  1C  |  24  |  2C  |  34  |  3C  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|         disp32         |     | 101 |  05  |  0D  |  15  |  1D  |  25  |  2D  |  35  |  3D  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|          [ESI]         |     | 110 |  06  |  0E  |  16  |  1E  |  26  |  2E  |  36  |  3E  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|          [EDI]         |     | 111 |  07  |  0F  |  17  |  1F  |  27  |  2F  |  37  |  3F  |
+------------------------+-----+-----+------+------+------+------+------+------+------+------+
|      [EAX] + disp8     |  01 | 000 |  40  |  48  |  50  |  58  |  60  |  68  |  70  |  78  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|      [ECX] + disp8     |     | 001 |  41  |  49  |  51  |  59  |  61  |  69  |  71  |  79  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|      [EDX] + disp8     |     | 010 |  42  |  4A  |  52  |  5A  |  62  |  6A  |  72  |  7A  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|      [EBX] + disp8     |     | 011 |  43  |  4B  |  53  |  5B  |  63  |  6B  |  73  |  7B  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|    [--][--] + disp8    |     | 100 |  44  |  4C  |  54  |  5C  |  64  |  6C  |  74  |  7C  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|      [EBP] + disp8     |     | 101 |  45  |  4D  |  55  |  5D  |  65  |  6D  |  75  |  7D  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|      [ESI] + disp8     |     | 110 |  46  |  4E  |  56  |  5E  |  66  |  6E  |  76  |  7E  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|      [EDI] + disp8     |     | 111 |  47  |  4F  |  57  |  5F  |  67  |  6F  |  77  |  7F  |
+------------------------+-----+-----+------+------+------+------+------+------+------+------+
|     [EAX] + disp32     |  10 | 000 |  80  |  88  |  90  |  98  |  A0  |  A8  |  B0  |  B8  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|     [ECX] + disp32     |     | 001 |  81  |  89  |  91  |  99  |  A1  |  A9  |  B1  |  B9  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|     [EDX] + disp32     |     | 010 |  82  |  8A  |  92  |  9A  |  A2  |  AA  |  B2  |  BA  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|     [EBX] + disp32     |     | 011 |  83  |  8B  |  93  |  9B  |  A3  |  AB  |  B3  |  BB  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|    [--][--] + disp32   |     | 100 |  84  |  8C  |  94  |  9C  |  A4  |  AC  |  B4  |  BC  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|     [EBP] + disp32     |     | 101 |  85  |  8D  |  95  |  9D  |  A5  |  AD  |  B5  |  BD  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|     [ESI] + disp32     |     | 110 |  86  |  8E  |  96  |  9E  |  A6  |  AE  |  B6  |  BE  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
|     [EDI] + disp32     |     | 111 |  87  |  8F  |  97  |  9F  |  A7  |  AF  |  B7  |  BF  |
+------------------------+-----+-----+------+------+------+------+------+------+------+------+
| EAX\/AX\/AL\/MM0\/XMM0 |  11 | 000 |  C0  |  C8  |  D0  |  D8  |  E0  |  E8  |  F0  |  F8  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
| ECX\/CX\/CL\/MM1\/XMM1 |     | 001 |  C1  |  C9  |  D1  |  D9  |  E1  |  E9  |  F1  |  F9  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
| EDX\/DX\/DL\/MM2\/XMM2 |     | 010 |  C2  |  CA  |  D2  |  DA  |  E2  |  EA  |  F2  |  FA  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
| EBX\/BX\/BL\/MM3\/XMM3 |     | 011 |  C3  |  CB  |  D3  |  DB  |  E3  |  EB  |  F3  |  FB  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
| ESP\/SP\/AH\/MM4\/XMM4 |     | 100 |  C4  |  CC  |  D4  |  DC  |  E4  |  EC  |  F4  |  FC  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
| EBP\/BP\/CH\/MM5\/XMM5 |     | 101 |  C5  |  CD  |  D5  |  DD  |  E5  |  ED  |  F5  |  FD  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
| ESI\/SI\/DH\/MM6\/XMM6 |     | 110 |  C6  |  CE  |  D6  |  DE  |  E6  |  EE  |  F6  |  FE  |
+------------------------+     +-----+------+------+------+------+------+------+------+------+
| EDI\/DI\/BH\/MM7\/XMM7 |     | 111 |  C7  |  CF  |  D7  |  DF  |  E7  |  EF  |  F7  |  FF  |
+------------------------+-----+-----+------+------+------+------+------+------+------+------+

=== NOTES:

1. The @[--][--]@ nomenclature means a SIB follows the ModR\/M byte.
2. The @disp32@ nomenclature denotes a 32-bit displacement that follows the ModR\/M byte (or the SIB byte if one is present) and that is
added to the index.
3. The @disp8@ nomenclature denotes an 8-bit displacement that follows the ModR\/M byte (or the SIB byte if one is present) and that is
sign-extended and added to the index.


===== Table generated from the Intel manual (Volume 2, Section 2.1) with the help of <https://www.tablesgenerator.com/text_tables>.
-}

-- | Creates the ModR\/M byte from the mode, the destination register and the source register\/memory.
modRM :: Word8    -- ^ Addressing mode
      -> Word8    -- ^ Destination register encoding, see 'registerNumber' for how to obtain it.
      -> Word8    -- ^ Source register encoding, see 'registerNumber' for how to obtain it.
      -> InterOpcode
modRM mod reg rm = Byte $
      ((mod .&. 0b11)  `shiftL` 6)
  .|. ((reg .&. 0b111) `shiftL` 3)
  .|. ((rm  .&. 0b111) `shiftL` 0)

-- | Creates the ModR\/M byte corresponding to moving from a register offset to a register (@N(reg_src) -> reg_dst@).
modRMRegOffsetIntoReg :: Register -> Register -> InterOpcode
modRMRegOffsetIntoReg rOff r2 = modRM 0b01 (registerNumber r2) (registerNumber rOff)

-- | Creates the ModR\/M byte corresponding to moving from a register as an offset to a register (@reg_offset(???) -> reg_dst@).
modRMRegAsOffsetIntoReg :: Register -> Register -> InterOpcode
modRMRegAsOffsetIntoReg rOff r2 = modRM 0b10 (registerNumber r2) (registerNumber rOff)

-- | Creates the ModR\/M byte corresponding to moving from a register to a register as an offset (@reg_src -> reg_offset(???)@).
modRMRegIntoRegAsOffset :: Register -> Register -> InterOpcode
modRMRegIntoRegAsOffset r1 rOff = modRM 0b10 (registerNumber rOff) (registerNumber r1)

-- | Creates the ModR\/M byte corresponding to moving between two registers.
modRMRegToReg :: Register -> Register -> InterOpcode
modRMRegToReg src dst = modRM 0b11 (registerNumber dst) (registerNumber src)
