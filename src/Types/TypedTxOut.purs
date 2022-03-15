module Types.TypedTxOut
  ( ConnectionError(..)
  , TypedTxOut
  , TypedTxOutRef
  , WrongOutTypeError(..)
  , mkTypedTxOut
  , typeTxOut
  , typeTxOutRef
  , typedTxOutAddress
  , typedTxOutDatumHash
  , typedTxOutRefAddress
  , typedTxOutRefDatumHash
  , typedTxOutRefValue
  , typedTxOutTxOut
  , typedTxOutValue
  ) where

-- DO NOT export data constructors for `TypedTxOut` and `TypedTxOutRef`.

import Prelude
import Address (ogmiosAddressToAddress)
import Control.Monad.Error.Class (throwError)
import Control.Monad.Except.Trans (ExceptT(ExceptT), runExceptT)
import Data.Either (Either, note)
import Data.Generic.Rep (class Generic)
import Data.Maybe (Maybe)
import Data.Newtype (unwrap, wrap)
import Data.Show.Generic (genericShow)
import FromData (class FromData, fromData)
import Helpers (liftM)
import QueryM (QueryM, getDatumByHash)
import Scripts (typedValidatorAddress)
import Serialization.Address (Address, NetworkId)
import ToData (class ToData, toData)
import Types.Datum (Datum(Datum), DatumHash, datumHash)
import Types.JsonWsp (OgmiosAddress, OgmiosTxOut)
import Types.PlutusData (PlutusData)
import Types.Transaction (TransactionInput, TransactionOutput)
import Types.TypedValidator
  ( class DatumType
  , TypedValidator
  )
import Types.Value (Value)
import TxOutput (ogmiosDatumHashToDatumHash)

-- | A `TxOutRef` ~ `TransactionInput` tagged by a phantom type: and the
-- | connection type of the output.
-- | Plutus uses wraps this type with a `TxIn` data type instead with optionally
-- | carries the address type. We don't include such a type in our setup.
-- | Note that `TypedTxOut` is implicitly constrained by its smart
-- | constructor.
newtype TypedTxOutRef (a :: Type) (b :: Type) = TypedTxOutRef
  { txOutRef :: TransactionInput, typedTxOut :: TypedTxOut a b }

-- `DatumType a b` not needed but this replicates Plutus and provides extra
-- type safety.
derive newtype instance (DatumType a b, Eq b) => Eq (TypedTxOutRef a b)

typedTxOutRefAddress
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TypedTxOutRef a b
  -> Address
typedTxOutRefAddress (TypedTxOutRef { typedTxOut }) =
  typedTxOutAddress typedTxOut

typedTxOutRefDatumHash
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TypedTxOutRef a b
  -> Maybe DatumHash
typedTxOutRefDatumHash (TypedTxOutRef { typedTxOut }) =
  typedTxOutDatumHash typedTxOut

typedTxOutRefValue
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TypedTxOutRef a b
  -> Value
typedTxOutRefValue (TypedTxOutRef { typedTxOut }) = typedTxOutValue typedTxOut

-- A `TransactionOutput` tagged by a phantom type: and the connection type of
-- the output. DO NOT import as extra constraints are required so only import
-- the smart constructor `mkTypedTxOut`
newtype TypedTxOut (a :: Type) (b :: Type) = TypedTxOut
  { txOut :: TransactionOutput, data :: b }

-- `DatumType a b` not needed but this replicates Plutus and provides extra
-- type safety.
derive newtype instance (DatumType a b, Eq b) => Eq (TypedTxOut a b)

typedTxOutAddress
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TypedTxOut a b
  -> Address
typedTxOutAddress (TypedTxOut { txOut }) = (unwrap txOut).address

typedTxOutDatumHash
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TypedTxOut a b
  -> Maybe DatumHash
typedTxOutDatumHash (TypedTxOut { txOut }) = (unwrap txOut).data_hash

typedTxOutValue
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TypedTxOut a b
  -> Value
typedTxOutValue (TypedTxOut { txOut }) = (unwrap txOut).amount

typedTxOutTxOut
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TypedTxOut a b
  -> TransactionOutput
typedTxOutTxOut (TypedTxOut { txOut }) = txOut

-- FIX ME: COMMENTS & EXPORTS
-- Purescript's lack of dependent types requires this smart constructor as we
-- cannot constrain the `TypedTxOut` datatype.
-- | Smart constructor to directly create a `TypedTxOut`, which is required
-- | because extra constraints are needed. The `TransactionOutput` is tagged by
-- | a phantom type.
mkTypedTxOut'
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => TransactionOutput
  -> b -- Data
  -> TypedTxOut a b
mkTypedTxOut' txOut dt = TypedTxOut { txOut, data: dt }

-- | Create a `TypedTxOut` from a network ID, a correctly-typed data
-- | script, an address, and a value.
mkTypedTxOut
  :: forall (a :: Type) (b :: Type)
   . DatumType a b
  => FromData b
  => ToData b
  => NetworkId
  -> TypedValidator a
  -> b
  -> Value
  -> Maybe (TypedTxOut a b)
mkTypedTxOut networkId typedVal dt amount = do
  dHash <- datumHash $ Datum $ toData dt
  let address = typedValidatorAddress networkId typedVal
  pure $ mkTypedTxOut' (wrap { address, amount, data_hash: pure dHash }) dt

data WrongOutTypeError = ExpectedScriptGotPubkey

-- | ExpectedPubkeyGotScript

derive instance Generic WrongOutTypeError _
derive instance Eq WrongOutTypeError
derive instance Ord WrongOutTypeError

instance Show WrongOutTypeError where
  show = genericShow

-- | An error we can get while trying to type an existing transaction part.
data ConnectionError
  = WrongValidatorAddress Address Address
  | WrongOutType WrongOutTypeError
  | WrongRedeemerType PlutusData
  | WrongDatumType PlutusData
  | CannotConvertOgmiosAddress OgmiosAddress
  | CannotConvertOgmiosDatumHash String -- FIX ME: Unify error?
  | CannotQueryDatum DatumHash
  | CannotMakeTypedTxOut
  | UnknownRef

derive instance Generic ConnectionError _
derive instance Eq ConnectionError
derive instance Ord ConnectionError

instance Show ConnectionError where
  show = genericShow

-- | Checks that the given validator hash is consistent with the actual validator.
checkValidatorAddress
  :: forall (a :: Type) (m :: Type -> Type)
   . Monad m
  => NetworkId
  -> TypedValidator a
  -> Address
  -> m (Either ConnectionError Unit)
checkValidatorAddress networkId typedVal actualAddr = runExceptT do
  let expectedAddr = typedValidatorAddress networkId typedVal
  unless (expectedAddr == actualAddr)
    $ throwError
    $ WrongValidatorAddress expectedAddr actualAddr

-- -- | Checks that the given redeemer script has the right type.
-- checkRedeemer
--   :: forall (a :: Type) (b :: Type) (m :: Type -> Type)
--    . Monad m
--   => RedeemerType a b
--   => FromData b
--   => TypedValidator a
--   -> Redeemer
--   -> m (Either ConnectionError b)
-- checkRedeemer _ (Redeemer pd) =
--   runExceptT $ liftM (WrongRedeemerType pd) (fromData pd :: Maybe b)

-- | Checks that the given datum has the right type.
checkDatum
  :: forall (a :: Type) (b :: Type) (m :: Type -> Type)
   . Monad m
  => DatumType a b
  => FromData b
  => TypedValidator a
  -> Datum
  -> m (Either ConnectionError b)
checkDatum _ (Datum pd) =
  runExceptT $ liftM (WrongDatumType pd) (fromData pd :: Maybe b)

-- | Create a `TypedTxOut` from an existing `TxOutRef` ~ `TransactionInput` by
-- | checking the types of its parts.
typeTxOut
  :: forall (a :: Type) (b :: Type) (m :: Type -> Type)
   . DatumType a b
  => FromData b
  => ToData b
  => NetworkId
  -> TypedValidator a
  -> OgmiosTxOut
  -> QueryM (Either ConnectionError (TypedTxOut a b))
typeTxOut networkId typedVal { address, value, datum } = runExceptT do
  -- Assume `Nothing` is a public key.
  datumStr <- liftM (WrongOutType ExpectedScriptGotPubkey) datum
  addr <- liftM
    (CannotConvertOgmiosAddress address)
    (ogmiosAddressToAddress address)
  void $ checkValidatorAddress networkId typedVal addr
  dHash <- liftM
    (CannotConvertOgmiosDatumHash datumStr)
    (ogmiosDatumHashToDatumHash datumStr)
  pd <- ExceptT $ getDatumByHash dHash <#> note (CannotQueryDatum dHash) -- Fix me: unify error
  dtOut <- ExceptT $ checkDatum typedVal (wrap pd)
  liftM
    CannotMakeTypedTxOut
    (mkTypedTxOut networkId typedVal dtOut value)

-- | Create a `TypedTxOutRef` from an existing `TxOutRef` ~ `TransactionInput`
-- | by checking the types of its parts. To do this we need to cross-reference
-- | against the validator script and be able to look up the `TxOutRef` to
-- | which this reference points.
typeTxOutRef
  :: forall (a :: Type) (b :: Type) (m :: Type -> Type)
   . DatumType a b
  => FromData b
  => ToData b
  => NetworkId
  -> (TransactionInput -> Maybe OgmiosTxOut)
  -> TypedValidator a
  -> TransactionInput
  -> QueryM (Either ConnectionError (TypedTxOutRef a b))
typeTxOutRef networkId lookupRef typedVal txOutRef = runExceptT do
  out <- liftM UnknownRef (lookupRef txOutRef)
  typedTxOut <- ExceptT $ typeTxOut networkId typedVal out
  pure $ TypedTxOutRef { txOutRef, typedTxOut }