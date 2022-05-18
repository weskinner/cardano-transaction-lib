module Ogmios.Parser (decodeProtocolParameters) where

import Cardano.Api (
  AnyPlutusScriptVersion (AnyPlutusScriptVersion),
  CostModel,
  ExecutionUnitPrices (ExecutionUnitPrices),
  ExecutionUnits,
  Lovelace (Lovelace),
  PlutusScriptVersion (PlutusScriptV1),
 )
import Cardano.Api.Shelley (ProtocolParameters (ProtocolParameters))

import Data.Text qualified as Text
import Text.Parsec qualified as Parsec
import Text.Parsec.Char qualified as Parsec.Char
import Text.ParserCombinators.Parsec.Combinator (many1)

import Data.Aeson qualified as Aeson
import Data.Aeson.BetterErrors (
  Parse,
  asIntegral,
  displayError,
  fromAesonParser,
  key,
  parseValue,
  perhaps,
  withString,
  (<|>),
 )
import Data.Bifunctor (first)
import Data.ByteString.Lazy (ByteString)
import Data.Char (isDigit)
import Data.Map qualified as Map
import Data.Ratio ((%))
import GHC.Natural (Natural, naturalFromInteger)

parseVersion :: Parse e (Natural, Natural)
parseVersion =
  key "protocolVersion" $
    (,) <$> parseNatural "major" <*> parseNatural "minor"

parseNatural :: Text.Text -> Parse e Natural
parseNatural strKey =
  naturalFromInteger <$> key strKey asIntegral

parseLovelace :: Text.Text -> Parse e Lovelace
parseLovelace strKey =
  key strKey $
    Lovelace <$> asIntegral

parseRational :: Text.Text -> Parse Text.Text Rational
parseRational strKey =
  key strKey (withString rationalParser)

parseExecutionPrices :: Parse Text.Text (Maybe ExecutionUnitPrices)
parseExecutionPrices =
  perhaps $
    ExecutionUnitPrices
      <$> parseRational "steps"
      <*> parseRational "memory"

parseExecutionUnits :: Parse e (Maybe ExecutionUnits)
parseExecutionUnits = fromAesonParser

parseCostModels :: Parse e (Map.Map AnyPlutusScriptVersion CostModel)
parseCostModels =
  Map.singleton (AnyPlutusScriptVersion PlutusScriptV1)
    <$> key "plutus:v1" fromAesonParser

parseResult :: Parse Text.Text ProtocolParameters
parseResult =
  key "result" $
    ProtocolParameters
      <$> parseVersion
      <*> parseRational "decentralizationParameter"
      -- TODO : How to parse the value `neutral` from ogmios?
      <*> pure Nothing -- key "extraEntropy" (perhaps (makePraosNonce . BLU.fromString <$>asString))
      <*> parseNatural "maxBlockHeaderSize"
      <*> parseNatural "maxBlockBodySize"
      <*> parseNatural "maxTxSize"
      <*> parseNatural "minFeeConstant" -- I think minFeeConstant and minFeeCoefficient are swapped here
      -- but this is consistent with the current config file.
      <*> parseNatural "minFeeCoefficient"
      <*> pure Nothing
      <*> parseLovelace "stakeKeyDeposit"
      <*> parseLovelace "poolDeposit"
      <*> parseLovelace "minPoolCost"
      <*> key "poolRetirementEpochBound" fromAesonParser
      <*> parseNatural "desiredNumberOfPools"
      <*> parseRational "poolInfluence"
      <*> parseRational "monetaryExpansion"
      <*> parseRational "treasuryExpansion"
      <*> perhaps (parseLovelace "coinsPerUtxoWord")
      <*> (key "costModels" parseCostModels <|> pure Map.empty)
      <*> key "prices" parseExecutionPrices
      <*> key "maxExecutionUnitsPerTransaction" parseExecutionUnits
      <*> key "maxExecutionUnitsPerBlock" parseExecutionUnits
      <*> perhaps (parseNatural "maxValueSize")
      <*> perhaps (parseNatural "collateralPercentage")
      <*> perhaps (parseNatural "maxCollateralInputs")

decodeProtocolParameters :: ByteString -> Either [Text.Text] ProtocolParameters
decodeProtocolParameters response =
  let value :: Maybe Aeson.Value
      value = Aeson.decode response
   in case parseValue parseResult <$> value of
        Just (Right params) -> Right params
        Just (Left e) -> Left $ displayError id e
        _ -> Left ["Fail at converting ogmios response to cardano format"]

type LocalParser a = Parsec.Parsec String () a

nonZeroDigit :: LocalParser Char
nonZeroDigit = Parsec.Char.satisfy (\c -> (c /= '0') && isDigit c)

nonZeroInteger :: LocalParser Integer
nonZeroInteger = do
  headDigit <- nonZeroDigit
  remains <- Parsec.many Parsec.Char.digit
  pure $ read (headDigit : remains)

zeroInteger :: LocalParser Integer
zeroInteger = read <$> many1 (Parsec.Char.satisfy (== '0'))

haskellInteger :: LocalParser Integer
haskellInteger = nonZeroInteger Parsec.<|> zeroInteger

rational :: LocalParser Rational
rational =
  do
    Parsec.Char.spaces
    numerator <- haskellInteger
    Parsec.Char.spaces >> Parsec.Char.char '/' >> Parsec.Char.spaces
    denominator <- haskellInteger
    pure $ numerator % denominator

rationalParser :: String -> Either Text.Text Rational
rationalParser s =
  first
    (const "can't parse Rational")
    $ Parsec.runParser rational () "ogmios.json" s
