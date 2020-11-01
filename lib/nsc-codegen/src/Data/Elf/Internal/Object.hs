module Data.Elf.Internal.Object where

import Data.Elf.Internal.FileHeader
import Data.Elf.Internal.ProgramHeader
import Data.Elf.Internal.SectionHeader
import Data.Elf.Internal.ToBytes (ToBytes(..))
import Data.Elf.Types (UChar)

data Object64
  = Obj64
      Elf64_Ehdr     -- ^ The file header
      [Elf64_Phdr]   -- ^ Programs headers
      [Elf64_Shdr]   -- ^ Section headers
      [UChar]        -- ^ Raw data

instance ToBytes Object64 where
  toBytes le (Obj64 fh phs shs bytes) = mconcat
    [ toBytes le fh
    , toBytes le phs
    , toBytes le shs
    , toBytes le bytes
    ]