-- | This module demonstrates how the `Contract` interface can be used to build,
-- | balance, and submit a smart-contract transaction. It creates a transaction
-- | that pays two Ada to the `AlwaysSucceeds` script address
module Examples.AlwaysSucceeds (main) where

import Contract.Prelude

import Contract.Monad (ContractConfig(ContractConfig), launchAff_, liftContractM, liftedE, liftedM, logInfo', runContract_, traceContractConfig, Contract)
import Contract.PlutusData (PlutusData, unitDatum)
import Contract.ScriptLookups as Lookups
import Contract.Scripts (Validator, validatorHash)
import Contract.Transaction (BalancedSignedTransaction(BalancedSignedTransaction), balanceAndSignTx, submit)
import Contract.TxConstraints (mustSpendScriptOutput)
import Contract.TxConstraints as Constraints
import Contract.Utxos (utxosAt)
import Contract.Value as Value
import Contract.Wallet (mkNamiWalletAff)
import Data.Argonaut (decodeJson, fromString)
import Data.BigInt as BigInt
import Plutus.Types.Address (scriptHashAddress)
import Plutus.Types.Credential (Credential(..))
import Types.PlutusData (PlutusData(Integer))
import Types.Scripts (ValidatorHash)
import Serialization.Address(Address)

main :: Effect Unit
main = launchAff_ $ do
  wallet <- Just <$> mkNamiWalletAff
  cfg <- over ContractConfig _ { wallet = wallet } <$> traceContractConfig
  runContract_ cfg $ do
    logInfo' "Running Examples.AlwaysSucceeds"
    validator <- liftContractM "Invalid script JSON" $ alwaysSucceedsScript
    vhash <- liftedM "Couldn't hash validator" $ validatorHash validator
    payToAlwaysSucceeds vhash validator


payToAlwaysSucceeds :: ValidatorHash -> Validator -> Contract () Unit
payToAlwaysSucceeds vhash validator = do
    let
      -- Note that CTL does not have explicit equivalents of Plutus'
      -- `mustPayToTheScript` or `mustPayToOtherScript`, as we have no notion
      -- of a "current" script. Thus, we have the single constraint
      -- `mustPayToScript`, and all scripts must be explicitly provided to build
      -- the transaction (see the value for `lookups` below as well)
      constraints :: Constraints.TxConstraints Unit Unit
      constraints = Constraints.mustPayToScript vhash unitDatum
        $ Value.lovelaceValueOf
        $ BigInt.fromInt 2_000_000

      lookups :: Lookups.ScriptLookups PlutusData
      lookups = Lookups.validator validator

    ubTx <- liftedE $ Lookups.mkUnbalancedTx lookups constraints
    BalancedSignedTransaction bsTx <-
      liftedM "Failed to balance/sign tx" $ balanceAndSignTx ubTx
    txId <- submit bsTx.signedTxCbor
    logInfo' $ "Tx ID: " <> show txId

spendFromAlwaysSucceeds :: ValidatorHash -> Validator -> Contract () Unit
spendFromAlwaysSucceeds vhash validator= do
  let 
    -- scriptAddress = scriptHashAddress vhash
    scriptAddress = Addres (ScriptCredential vhash) Nothing
  utxos <- utxosAt scriptAddress
  let
    constraints = 
      Constraints.mustSpendScriptOutput 2 (Integer 1)
  undefined

alwaysSucceedsScript :: Maybe Validator
alwaysSucceedsScript = map wrap $ hush $ decodeJson $ fromString
  "4d01000033222220051200120011"
