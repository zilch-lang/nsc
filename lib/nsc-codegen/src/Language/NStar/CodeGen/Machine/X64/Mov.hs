module Language.NStar.CodeGen.Machine.X64.Mov
( -- * Instruction encoding
  -- $encoding

  -- * Compiling
compileMov
) where

import Language.NStar.Syntax.Core (Expr(..), Type, Immediate(..))
import Language.NStar.CodeGen.Compiler (Compiler)
import Language.NStar.CodeGen.Machine.Internal.Intermediate (InterOpcode(..))
import Data.Located (Located((:@)), unLoc)
import Internal.Error (internalError)
import Language.NStar.CodeGen.Machine.Internal.X64.REX (rexW)
import Language.NStar.CodeGen.Machine.Internal.X64.SIB (sib)
import Language.NStar.CodeGen.Machine.Internal.X64.ModRM (modRM)
import Language.NStar.CodeGen.Machine.X64.Expression (int8, compileExprX64)
import Language.NStar.CodeGen.Machine.Internal.X64.RegisterEncoding (registerNumber)

{- $encoding

+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       Opcode      |       Instruction       | Op/En | 64-bit Mode | Compat/Leg Mode |                           Description                          |
+===================+=========================+=======+=============+=================+================================================================+
|       88 /r       |       MOV r/m8,r8       |   MR  |    Valid    |      Valid      |                        Move r8 to r/m8.                        |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|    REX + 88 /r    |    MOV r/m8***,r8***    |   MR  |    Valid    |       N.E.      |                        Move r8 to r/m8.                        |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       89 /r       |      MOV r/m16,r16      |   MR  |    Valid    |      Valid      |                       Move r16 to r/m16.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       89 /r       |      MOV r/m32,r32      |   MR  |    Valid    |      Valid      |                       Move r32 to r/m32.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|   REX.W + 89 /r   |      MOV r/m64,r64      |   MR  |    Valid    |       N.E.      |                       Move r64 to r/m64.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       8A /r       |       MOV r8,r/m8       |   RM  |    Valid    |      Valid      |                        Move r/m8 to r8.                        |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|    REX + 8A /r    |    MOV r8***,r/m8***    |   RM  |    Valid    |       N.E.      |                        Move r/m8 to r8.                        |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       8B /r       |      MOV r16,r/m16      |   RM  |    Valid    |      Valid      |                       Move r/m16 to r16.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       8B /r       |      MOV r32,r/m32      |   RM  |    Valid    |      Valid      |                       Move r/m32 to r32.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|   REX.W + 8B /r   |      MOV r64,r/m64      |   RM  |    Valid    |       N.E.      |                       Move r/m64 to r64.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       8C /r       |     MOV r/m16,Sreg**    |   MR  |    Valid    |      Valid      |                 Move segment register to r/m16.                |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|   REX.W + 8C /r   | MOV r16/r32/m16, Sreg** |   MR  |    Valid    |      Valid      | Move zero extended 16-bit segment register to r16/r32/r64/m16. |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|   REX.W + 8C /r   |   MOV r64/m16, Sreg**   |   MR  |    Valid    |      Valid      |     Move zero extended 16-bit segment register to r64/m16.     |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|       8E /r       |     MOV Sreg,r/m16**    |   RM  |    Valid    |      Valid      |                 Move r/m16 to segment register.                |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|   REX.W + 8E /r   |     MOV Sreg,r/m64**    |   RM  |    Valid    |      Valid      |        Move lower 16 bits of r/m64 to segment register.        |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|         A0        |      MOV AL,moffs8*     |   FD  |    Valid    |      Valid      |                Move byte at (seg:offset) to AL.                |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|     REX.W + A0    |      MOV AL,moffs8*     |   FD  |    Valid    |       N.E.      |                  Move byte at (offset) to AL.                  |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|         A1        |     MOV AX,moffs16*     |   FD  |    Valid    |      Valid      |                Move word at (seg:offset) to AX.                |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|         A1        |     MOV EAX,moffs32*    |   FD  |    Valid    |      Valid      |             Move doubleword at (seg:offset) to EAX.            |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|     REX.W + A1    |     MOV RAX,moffs64*    |   FD  |    Valid    |       N.E.      |                Move quadword at (offset) to RAX.               |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|         A2        |      MOV moffs8,AL      |   TD  |    Valid    |      Valid      |                    Move AL to (seg:offset).                    |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|     REX.W + A2    |     MOV moffs8***,AL    |   TD  |    Valid    |       N.E.      |                      Move AL to (offset).                      |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|         A3        |     MOV moffs16*,AX     |   TD  |    Valid    |      Valid      |                    Move AX to (seg:offset).                    |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|         A3        |     MOV moffs32*,EAX    |   TD  |    Valid    |      Valid      |                    Move EAX to (seg:offset).                   |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|     REX.W + A3    |     MOV moffs64*,RAX    |   TD  |    Valid    |       N.E.      |                      Move RAX to (offset).                     |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|     B0+ rb ib     |       MOV r8, imm8      |   OI  |    Valid    |      Valid      |                        Move imm8 to r8.                        |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|  REX + B0+ rb ib  |     MOV r8***, imm8     |   OI  |    Valid    |       N.E.      |                        Move imm8 to r8.                        |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|     B8+ rw iw     |      MOV r16, imm16     |   OI  |    Valid    |      Valid      |                       Move imm16 to r16.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|     B8+ rd id     |      MOV r32, imm32     |   OI  |    Valid    |      Valid      |                       Move imm32 to r32.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
| REX.W + B8+ rd io |      MOV r64, imm64     |   OI  |    Valid    |       N.E.      |                       Move imm64 to r64.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|      C6 /0 ib     |      MOV r/m8, imm8     |   MI  |    Valid    |      Valid      |                       Move imm8 to r/m8.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|   REX + C6 /0 ib  |    MOV r/m8***, imm8    |   MI  |    Valid    |       N.E.      |                       Move imm8 to r/m8.                       |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|      C7 /0 iw     |     MOV r/m16, imm16    |   MI  |    Valid    |      Valid      |                      Move imm16 to r/m16.                      |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|      C7 /0 id     |     MOV r/m32, imm32    |   MI  |    Valid    |      Valid      |                      Move imm32 to r/m32.                      |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+
|  REX.W + C7 /0 id |     MOV r/m64, imm32    |   MI  |    Valid    |       N.E.      |          Move imm32 sign extended to 64-bits to r/m64.         |
+-------------------+-------------------------+-------+-------------+-----------------+----------------------------------------------------------------+

- * The moffs8, moffs16, moffs32 and moffs64 operands specify a simple offset relative to the segment base, where 8, 16, 32 and 64 refer to the size of the data.
    The address-size attribute of the instruction determines the size of the offset, either 16, 32 or 64 bits.
- ** In 32-bit mode, the assembler may insert the 16-bit operand-size prefix with this instruction.
- *** In 64-bit mode, r/m8 can not be encoded to access the following byte registers if a REX prefix is used: AH, BH, CH, DH.

< > {- Blank line -}

+-------+-----------------+---------------+-----------+-----------+
| Op/En |    Operand 1    |   Operand 2   | Operand 3 | Operand 4 |
+=======+=================+===============+===========+===========+
|   MR  |  ModRM:r/m (w)  | ModRM:reg (r) |     NA    |     NA    |
+-------+-----------------+---------------+-----------+-----------+
|   RM  |  ModRM:reg (w)  | ModRM:r/m (r) |     NA    |     NA    |
+-------+-----------------+---------------+-----------+-----------+
|   FD  |  AL/AX/EAX/RAX  |     Moffs     |     NA    |     NA    |
+-------+-----------------+---------------+-----------+-----------+
|   TD  |    Moffs (w)    | AL/AX/EAX/RAX |     NA    |     NA    |
+-------+-----------------+---------------+-----------+-----------+
|   OI  | opcode + rd (w) | imm8/16/32/64 |     NA    |     NA    |
+-------+-----------------+---------------+-----------+-----------+
|   MI  |  ModRM:r/m (w)  | imm8/16/32/64 |     NA    |     NA    |
+-------+-----------------+---------------+-----------+-----------+

-}

compileMov :: Expr -> Expr -> [Type] -> Compiler [InterOpcode]
compileMov (Reg src) (Reg dst) [_, _]                                         =
  pure [rexW, Byte 0x8B, modRM 0x3 (registerNumber (unLoc dst)) (registerNumber (unLoc src))]
compileMov src@(Imm _) (Reg dst) [_, _]                                       =
  mappend [rexW, Byte $ 0xB8 + registerNumber (unLoc dst)] <$> compileExprX64 64 src
compileMov (Name n) (Reg dst) [_, _]                                          =
  pure [rexW, Byte $ 0xB8 + registerNumber (unLoc dst), Symbol64 (unLoc n)]
compileMov (Indexed (Reg r1 :@ _) (Reg r2 :@ _)) (Reg dst) [_, _]             =
  pure [rexW, Byte 0x8B, modRM 0x0 (registerNumber (unLoc dst)) 0x4, sib 0x0 (registerNumber (unLoc r1)) (registerNumber (unLoc r2))]
compileMov (Reg src) (Indexed (Reg r1 :@ _) (Reg r2 :@ _)) [_, _]             =
  pure [rexW, Byte 0x89, modRM 0x0 (registerNumber (unLoc src)) 0x4, sib 0x0 (registerNumber (unLoc r1)) (registerNumber (unLoc r2))]
compileMov (Indexed (Reg r1 :@ _) (Name n :@ _)) (Reg dst) [_, _]             =
  pure [rexW, Byte 0x8B, modRM 0x2 (registerNumber (unLoc dst)) (registerNumber (unLoc r1)), Symbol32 (unLoc n) 0]
compileMov (Indexed (Imm (I disp :@ _) :@ _) (Name l :@ _)) (Reg dst) [_, _]  =
  pure [rexW, Byte 0x8B, modRM 0x0 (registerNumber (unLoc dst)) 0x4, sib 0x0 0x4 0x5, Symbol32 (unLoc l) disp]
compileMov (Indexed (Imm (I disp :@ _) :@ _) (Reg src :@ _)) (Reg dst) [_, _] =
  pure $ [rexW, Byte 0x8B, modRM 0x1 (registerNumber (unLoc dst)) (registerNumber (unLoc src))] <> (Byte <$> int8 disp)
compileMov (Indexed (Reg r1 :@ _) (Name n :@ _)) (Reg dst) [_, _]             =
  pure [rexW, Byte 0x8B, modRM 0x2 (registerNumber (unLoc dst)) (registerNumber (unLoc r1)), Symbol32 (unLoc n) 0]
compileMov src dst ts                                                         =
  internalError $ "Unsupported instruction 'mov " <> show src <> "," <> show dst <> " " <> show ts <> "'."