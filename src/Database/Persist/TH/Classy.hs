{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TemplateHaskellQuotes #-}

module Database.Persist.TH.Classy where

import Control.Lens (Lens')
import Data.Char qualified as Char
import Data.Text qualified as T
import Data.Traversable (forM)
import Database.Persist
import Database.Persist.EntityDef.Internal
import Database.Persist.Quasi.Internal
import Language.Haskell.TH.Lib
import Language.Haskell.TH.Quote
import Language.Haskell.TH.Syntax

-- | Generate something like:
--
--     class HasName ev a | ev -> a where
--       name :: Lens' ev a
mkClassyClass ::
  -- | like "name"
  String ->
  Q [Dec]
mkClassyClass name =
  -- \| like "Name"
  let nameCapitalized =
        case name of
          "" -> ""
          (x : xs) -> Char.toUpper x : xs
      -- \| like "HasName"
      hasName = "Has" <> nameCapitalized
   in return
        [ ClassD
            []
            (mkName hasName)
            [PlainTV (mkName "ev") (), PlainTV (mkName "a") ()]
            [FunDep [mkName "ev"] [mkName "a"]]
            [ SigD
                (mkName name)
                ( AppT
                    (AppT (ConT (mkName "Lens'")) (VarT (mkName "ev")))
                    (VarT (mkName "a"))
                )
            ]
        ]

-- | Generate something like:
--
-- instance HasName Person String where
--   name = (lens personName) (\ x y -> x {personName = y})
mkClassyInstances :: [UnboundEntityDef] -> Q [Dec]
mkClassyInstances defs = do
  concat <$> mapM mkClassyInstance defs

mkClassyInstance :: UnboundEntityDef -> Q [Dec]
mkClassyInstance ued = do
  forM (unboundEntityFields ued) $ \UnboundFieldDef {..} ->
    case unboundFieldType of
      FTTypeCon tmodule tname -> do
        let _unused = ()
            -- \| like "Person"
            instanceTypeName =
              ConT (mkName (T.unpack (unEntityNameHS $ getUnboundEntityNameHS ued)))
            -- \| like "person"
            instanceTypeNameLowerFirstChar =
              case T.unpack (unEntityNameHS $ getUnboundEntityNameHS ued) of
                "" -> ""
                (x : xs) -> Char.toLower x : xs
            -- \| like "Name"
            fieldUpperFirstChar =
              case T.unpack (unFieldNameHS unboundFieldNameHS) of
                "" -> ""
                (x : xs) -> Char.toUpper x : xs
            -- \| like "HasName"
            instanceHasName = mkName ("Has" <> fieldUpperFirstChar)
            -- \| like "personName"
            fieldLongName =
              mkName (instanceTypeNameLowerFirstChar ++ fieldUpperFirstChar)
            fieldClause =
              Clause
                []
                ( NormalB
                    ( AppE
                        (AppE (VarE (mkName "lens")) (VarE fieldLongName))
                        ( LamE
                            [VarP (mkName "x"), VarP (mkName "y")]
                            ( RecUpdE
                                (VarE (mkName "x"))
                                [(fieldLongName, VarE (mkName "y"))]
                            )
                        )
                    )
                )
                []
            field =
              FunD
                (mkName (T.unpack (unFieldNameHS unboundFieldNameHS)))
                [fieldClause]
            fieldTName =
              let tnameAndModule = case tmodule of
                    Nothing -> tname
                    Just t -> t <> "." <> tname
                  nonMaybe = ConT (mkName (T.unpack tnameAndModule))
               in case FieldAttrMaybe `elem` unboundFieldAttrs of
                    False -> nonMaybe
                    True -> AppT (ConT (mkName "Maybe")) nonMaybe
        return $
          InstanceD
            Nothing
            []
            ((AppT (AppT (ConT instanceHasName) instanceTypeName) fieldTName))
            [field]
