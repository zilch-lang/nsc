{-# LANGUAGE GADTs #-}
{-# LANGUAGE StandaloneDeriving #-}

{-|
  Module: Language.NStar.Typechecker.Core
  Description: NStar's typechecking core language
  Copyright: (c) Mesabloo, 2020
  License: BSD3
  Stability: experimental
-}

module Language.NStar.Typechecker.Core
(
  TypedProgram(..)
, TypedDataSection(..), TypedRODataSection(..), TypedUDataSection(..), TypedCodeSection(..)
, TypedStatement(..)
, TypedInstruction(..)
,  -- * Re-exports
  module Language.NStar.Syntax.Core
) where

import Language.NStar.Syntax.Core (Expr(..), Type(..), Kind(..), Register(..), Binding(..))
import Data.Located (Located)
import Data.Text (Text)
import Data.Map (Map)

data TypedProgram =
  TProgram
    (Located TypedDataSection)
    (Located TypedRODataSection)
    (Located TypedUDataSection)
    (Located TypedCodeSection)

data TypedDataSection where
  TData :: [Located Binding]
        -> TypedDataSection

data TypedRODataSection where
  TROData :: [()]
          -> TypedRODataSection

data TypedUDataSection where
  TUData :: [()]
         -> TypedUDataSection

data TypedCodeSection where
  TCode :: [Located TypedStatement]
        -> TypedCodeSection

data TypedStatement where
  -- | A label stripped off its context.
  TLabel :: Located Text         -- ^ the name of the label
         -> [TypedStatement]     -- ^ Label's scope
         -> TypedStatement
  -- | An instruction with type information attached to it.
  TInstr :: Located TypedInstruction  -- ^ the typed instruction
         -> TypedStatement

deriving instance Show TypedStatement

data TypedInstruction where
  RET :: Located Register
      -> TypedInstruction
  JMP :: Located Text
      -> TypedInstruction
  CALL :: Located Text
       -> TypedInstruction
  NOP :: TypedInstruction
  MV :: Located Expr
     -> Located Expr
     -> TypedInstruction
  SALLOC :: Located Integer
         -> TypedInstruction

deriving instance Show TypedInstruction
