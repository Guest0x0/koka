module Core.Specialize where

import Data.Map (Map)
import qualified Data.Map as M
import Data.Maybe (mapMaybe)
import Data.List (elemIndex)
import Control.Monad

import Common.Name
import Common.NameMap (NameMap)
import Common.NameSet (NameSet)
import qualified Common.NameSet as S
import Core.Core
import Core.Pretty ()
import Lib.Trace

data SpecializeDef = SpecializeDef
  { targetFunc :: Name
  , argToSpecialize :: Int
  } deriving (Show)

extractSpecializeDefs :: DefGroups -> NameMap SpecializeDef
extractSpecializeDefs = 
  M.fromList 
  . map (\specDef@SpecializeDef {targetFunc=target} -> (target, specDef)) 
  . concatMap getInline 
  . allDefs

calledInThisDef :: Def -> NameSet
calledInThisDef def = foldMapExpr go $ defExpr def
  where 
    go (App (Var (TName name _) _) xs) = S.singleton name
    go _ = S.empty

passedRecursivelyToThisDef :: Def -> NameMap Int
passedRecursivelyToThisDef def 
  -- TODO: FunDef type to avoid this check?
  | Lam args effect body <- defExpr def = foldMapExpr (go args) $ defExpr def
  | TypeLam _ (Lam params effect body) <- defExpr def = foldMapExpr (go params) $ defExpr def
  | otherwise = M.empty
  where
    go :: [TName] -> Expr -> Map Name Int
    go params (App (Var (TName name _) _) args)
      | name == defName def = doWork args params
    go params (App (TypeApp (Var (TName name _) _) _) args)
      | name == defName def = doWork args params
    go params _ = M.empty

    doWork :: [Expr] -> [TName] -> Map Name Int
    doWork args params =
      M.fromList $
        flip mapMaybe (zip3 [0..] args params) $ \(i, arg, param) ->
          case arg of
            Var tname _ | tname == param -> Just (getName tname, i)
            _ -> Nothing

getInline :: Def -> [SpecializeDef]
getInline def = map (\(k, v) -> SpecializeDef (defName def) v) $ M.toList $ M.filterWithKey (\k v -> k `S.member` calledInThisDef def) (passedRecursivelyToThisDef def)

allDefs :: DefGroups -> [Def]
allDefs = concatMap handleGroup
  where
    handleGroup (DefNonRec def) = [def]
    handleGroup (DefRec defs) = defs