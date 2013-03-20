{-# LANGUAGE TypeSynonymInstances, FlexibleInstances #-}
module CSPM.Evaluator.DeclBind (
    bindDecls, 
) where

import Data.List (partition)

import CSPM.DataStructures.Names
import CSPM.DataStructures.Syntax
import CSPM.DataStructures.Types
import CSPM.Evaluator.BuiltInFunctions
import CSPM.Evaluator.Dot
import CSPM.Evaluator.Exceptions
import {-# SOURCE #-} CSPM.Evaluator.Expr
import CSPM.Evaluator.Monad
import CSPM.Evaluator.PatBind
import CSPM.Evaluator.Values
import CSPM.Evaluator.ValueSet
import Util.Annotated
import Util.Monad

-- | Given a list of declarations, returns a sequence of names bounds to
-- values that can be passed to 'addScopeAndBind' in order to bind them in
-- the current scope.
bindDecls :: [TCDecl] -> EvaluationMonad [(Name, EvaluationMonad Value)]
bindDecls ds = do
    nvs <- concatMapM bindDecl ds 
    let eventsName = builtInName "Events"
        (eventNvs, normalNvs) = partition (\x -> fst x == eventsName) nvs
        computeEvents vs = do
            vss <- sequence (map snd eventNvs)
            return $ VSet $ infiniteUnions $ vs : map (\ (VSet s) -> s) vss

        isChannelDecl (Channel _ _) = True
        isChannelDecl _ = False

    if or (map (isChannelDecl . unAnnotate) ds) then do
        -- Lookup the existing value of events and add to it
        VSet vs <- lookupVar eventsName
        return $ (eventsName, computeEvents vs)  : normalNvs
    else return nvs

bindDecl :: TCDecl -> EvaluationMonad [(Name, EvaluationMonad Value)]
bindDecl (an@(An _ _ (FunBind n ms))) = do
    parentScope <- getParentScopeIdentifier
    let
        matches = map unAnnotate ms
        argGroupCount = head (map (\ (Match pss e) -> length pss) matches)
        collectArgs :: Int -> [[Value]] -> EvaluationMonad Value
        collectArgs 0 ass_ =
            let
                scopeName = scopeId n argGroups parentScope
                argGroups = reverse ass_
                tryMatches [] = throwError $ 
                    funBindPatternMatchFailureMessage (loc an) n argGroups
                tryMatches (Match pss e : ms) =
                    let 
                        bindResult = zipWith bindAll pss argGroups
                        (bindResults, boundValuess) = unzip bindResult
                        binds = concat boundValuess
                    in 
                        if not (and bindResults) then tryMatches ms
                        else
                            addScopeAndBind binds $ updateParentScopeIdentifier scopeName $ do
                                v <- eval e
                                case v of
                                    VProc p -> return $ VProc $ PProcCall (procName scopeName) p
                                    _ -> return $ v
            in tryMatches matches
        collectArgs number ass = do
            -- Make sure we save the enclosing environment (as it contains
            -- variables that we need).
            st <- gets id
            let fid = FMatchBind n (reverse ass) parentScope
            return $ VFunction fid $ \ vs ->
                modify (\_ -> st) $ collectArgs (number-1) (vs:ass)
    return $ [(n, collectArgs argGroupCount [])]
bindDecl (an@(An _ _ (PatBind p e))) = do
    parentScope <- getParentScopeIdentifier
    let [(n, ForAll _ t)] = getSymbolTable an
        scopeName = scopeId n [] parentScope
        ev = maybeSave t $ updateParentScopeIdentifier scopeName $ do
            v <- eval e
            case bind p v of
                (True, [(n', val)]) | n == n' -> return $!
                    case val of
                        VProc p -> VProc $ PProcCall (procName scopeName) p
                        _ ->  val
                (False, _) -> throwError $ 
                    patternMatchFailureMessage (loc an) p v
    return $ [(n, ev)]
bindDecl (an@(An _ _ (Channel ns me))) =
    let
        mkChan :: Name -> EvaluationMonad Value
        mkChan n = do
            fields <- case me of
                Just e -> eval e >>= evalTypeExprToList n
                Nothing -> return []
            let arity = fromIntegral (length fields)
            return $! tupleFromList [VDot [VChannel n], VInt arity, tupleFromList (map VSet fields)]
        eventSetValue :: EvaluationMonad Value
        eventSetValue = do
            ss <- mapM (\ n -> do
                (_, _, fields) <- dataTypeInfo n
                let fs = fromList [VChannel n] : elems fields
                return $ cartesianProduct CartDot fs) ns
            return $ VSet (infiniteUnions ss)
    -- We bind to events here, and this is picked up in bindDecls
    in return $ (builtInName "Events", eventSetValue) : [(n, mkChan n) | n <- ns]
bindDecl (an@(An _ _ (DataType n cs))) =
    let
        mkDataTypeClause :: DataTypeClause Name -> (Name, EvaluationMonad Value)
        mkDataTypeClause (DataTypeClause nc me) = (nc, do
            vss <- case me of
                Just e -> eval e >>= evalTypeExprToList nc
                Nothing -> return []
            let arity = fromIntegral (length vss)
            return $ tupleFromList [VDot [VDataType nc], VInt arity, tupleFromList (map VSet vss)])
        computeSetOfValues :: EvaluationMonad Value
        computeSetOfValues =
            let 
                mkSet nc = do
                    (_, _, fields) <- dataTypeInfo nc
                    let fs = fromList [VDataType nc] : elems fields
                    return $ cartesianProduct CartDot fs
            in do
                vs <- mapM mkSet [nc | DataTypeClause nc _ <- map unAnnotate cs]
                return $ VSet (infiniteUnions vs)
    in return $ (n, computeSetOfValues):(map mkDataTypeClause (map unAnnotate cs))
bindDecl (an@(An _ _ (SubType n cs))) =
    let
        computeSetOfValues =
            let 
                mkSet (DataTypeClause nc me) = do
                    (_, _, fields) <- dataTypeInfo nc
                    fs <- case me of
                            Just e -> eval e >>= evalTypeExprToList nc
                            Nothing -> return []
                    let s = cartesianProduct CartDot (fromList [VDataType nc] : fs)
                    vs <- mapM productionsSet (toList s)
                    return (infiniteUnions vs)
            in do
                vs <- mapM (mkSet . unAnnotate) cs
                return $ VSet (infiniteUnions vs)
    in return $ [(n, computeSetOfValues)]
bindDecl (an@(An _ _ (NameType n e))) = return $
    [(n, do
        v <- eval e
        sets <- evalTypeExprToList n v
        -- If we only have one set then this is not a cartesian product, this is
        -- just introducing another name (see TPC P543 and
        -- evaluator/should_pass/nametypes.csp).
        case sets of
            [s] -> return $ VSet s
            _ -> return $ VSet $ cartesianProduct CartDot sets)]
bindDecl (an@(An _ _ (Assert _))) = return []
bindDecl (an@(An _ _ (External ns))) = return []
bindDecl (an@(An _ _ (Transparent ns))) = return []
bindDecl (an@(An _ _ (TimedSection (Just tn) f ds))) = do
    nds <- concatMapM bindDecl ds
    let packageDecl :: EvaluationMonad Value -> EvaluationMonad Value
        packageDecl value = do
            VFunction _ wrappedFunc <- eval f
            st <- gets id
            let func (UserEvent v) = c
                    where VInt c = runEvaluator st (wrappedFunc [v])
            return $! runEvaluator st $ setTimedCSP tn func value
    return $! map (\ (n,d) -> (n, packageDecl d)) nds

evalTypeExpr :: Value -> ValueSet
evalTypeExpr (VSet s) = s
evalTypeExpr (VTuple vs) = cartesianProduct CartTuple (map evalTypeExpr (elems vs))

evalTypeExprToList :: Name -> Value -> EvaluationMonad [ValueSet]
evalTypeExprToList n (VDot vs) = concatMapM (evalTypeExprToList n) vs
evalTypeExprToList n v = splitIntoFields False n (evalTypeExpr v)
