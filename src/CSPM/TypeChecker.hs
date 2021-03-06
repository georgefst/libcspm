{-# LANGUAGE FlexibleContexts #-}
module CSPM.TypeChecker (
    typeCheck, typeCheckExpect,
    typeOfExp, typeOfName,

    ErrorOptions, modifyErrorOptions,

    initTypeChecker,
    TypeCheckMonad, TypeInferenceState,
    runTypeChecker, runFromStateToState,
) where

import Control.Monad.Trans

import CSPM.Syntax.Names
import CSPM.Syntax.AST hiding (getType)
import CSPM.Syntax.Types
import CSPM.TypeChecker.BuiltInFunctions
import qualified CSPM.TypeChecker.Common as TC
import CSPM.TypeChecker.Compressor
import CSPM.TypeChecker.Exceptions
import CSPM.TypeChecker.Expr()
import CSPM.TypeChecker.File()
import CSPM.TypeChecker.InteractiveStmt()
import CSPM.TypeChecker.Monad
import CSPM.TypeChecker.Unification
import Util.Annotated
import Util.Exception

runFromStateToState :: TypeInferenceState -> TypeCheckMonad a -> 
            IO (a, [ErrorMessage], TypeInferenceState)
runFromStateToState st prog = runTypeChecker st $ do
    r <- prog
    ws <- getWarnings
    resetWarnings
    s <- getState
    return (r, ws, s)

initTypeChecker :: IO TypeInferenceState
initTypeChecker = runTypeChecker newTypeInferenceState $ do
    injectBuiltInFunctions
    -- Add a blank level in the environment to allow built in functions
    -- to be overriden.
    local [] getState

typeCheckExpect :: (Compressable a, TC.TypeCheckable a Type) => Type -> a -> TypeCheckMonad a
typeCheckExpect t exp = TC.typeCheckExpect exp t >> liftIO (mcompress exp)

typeCheck :: (Compressable a, TC.TypeCheckable a b) => a -> TypeCheckMonad a
typeCheck exp = TC.typeCheck exp >> liftIO (mcompress exp)

typeOfExp :: TCExp -> TypeCheckMonad Type
typeOfExp exp = do
    -- See if has been type checked, if so, return type,
    -- else type check
    mt <- liftIO $ readPType (snd (annotation exp))
    case mt of 
        Just t -> evaluateDots t >>= compress
        Nothing -> typeCheck exp >> typeOfExp exp

typeOfName :: Name -> TypeCheckMonad TypeScheme
typeOfName = getType
