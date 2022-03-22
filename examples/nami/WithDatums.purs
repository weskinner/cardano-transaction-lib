module Examples.Nami.WithDatums (main) where

import Contract.Prelude

import Contract.Monad (Contract, defaultContractConfig, runContract)
import Contract.PlutusData (unitDatum)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (Validator, validatorHash)
import Contract.Transaction (TransactionHash, balanceTx, submitTransaction)
import Contract.TxConstraints as Constraints
import Contract.Value (lovelaceValueOf)
import Data.Argonaut (decodeJson, parseJson)
import Data.BigInt as BigInt
import Effect (Effect)
import Effect.Aff (error, launchAff_, throwError)

main :: Effect Unit
main = launchAff_ $ do
  cfg <- defaultContractConfig
  runContract cfg $ do
    payToAlwaysSucceeds

payToAlwaysSucceeds :: Contract (Maybe TransactionHash)
payToAlwaysSucceeds = do
  validator <- throwOnNothing "Got `Nothing` for validator"
    alwaysSucceedsValidator
  valHash <-
    throwOnNothing "Got `Nothing` for validator hash"
    =<< validatorHash validator
  let
    constraints :: Constraints.TxConstraints Void Void
    constraints = Constraints.mustPayToOtherScript valHash unitDatum
      $ lovelaceValueOf
      $ BigInt.fromInt 1000

    lookups :: Maybe (Lookups.ScriptLookups Void)
    lookups = Lookups.otherScriptM validator

  unbalancedTx <- throwOnLeft
    =<< flip Lookups.mkUnbalancedTx constraints
    =<< throwOnNothing "Lookups were `Nothing`" lookups
  balancedTx <- throwOnLeft =<< balanceTx unbalancedTx
  submitTransaction balancedTx

alwaysSucceedsValidator :: Maybe Validator
alwaysSucceedsValidator = hush
  $ decodeJson
  =<< parseJson "\"4d01000033222220051200120011\""

throwOnLeft
  :: forall (a :: Type) (e :: Type). Show e => Either e a -> Contract a
throwOnLeft = either (throwError <<< error <<< show) pure

throwOnNothing :: forall (a :: Type). String -> Maybe a -> Contract a
throwOnNothing msg = maybe (throwError $ error msg) pure