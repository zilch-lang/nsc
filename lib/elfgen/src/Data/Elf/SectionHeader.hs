{-# LANGUAGE BangPatterns #-}

module Data.Elf.SectionHeader
( SectionHeader(..)
, module Data.Elf.SectionHeader.Flags
) where

import Data.Elf.Types
import Data.Word (Word8)
import Data.Elf.SectionHeader.Flags
import Data.Elf.Symbol

-- | Section header
data SectionHeader n
  -- | Section header table entry unused
  = SNull
  -- | Program data
  | SProgBits
      String
      [Word8]
      (SFlags n)
  -- | Relocation entries with addends
  | SRela
      String
      [RelocationSymbol n]
  -- | Program space with no data (bss)
  | SNoBits
      String
      Integer   -- ^ Space size
      (SFlags n)
  -- | Symbol table
  | SSymTab
      String
      [ElfSymbol n]
  -- | String table
  | SStrTab
      String
      [String]

deriving instance Eq (SectionHeader n)
deriving instance Ord (SectionHeader n)
