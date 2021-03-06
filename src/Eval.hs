module Eval where

import           Control.Exception
import           Control.Monad.State.Strict
import           Data.Either.Combinators
import           Env
import           Parse
import           Safe
import           System.Console.Repl
import           Types

push :: LispVal -> LispM ()
push val = do
  modify addFrame
  printStack "->"
  where addFrame xs =
          Callframe val : xs

pop :: LispM ()
pop = do
  modify tailSafe
  printStack "<-"


printStack :: String -> LispM ()
printStack msg = do
  stack <- get
  liftIO $ putStrLn $ msg ++ " " ++ unwords (map show (headSafe stack))
  where headSafe []     = []
        headSafe (x:xs) = [x]


{- Eval -}
eval :: Env -> LispVal -> LispM LispVal
eval env val =
  case val of
    Symbol s ->
      getVar env s

    List [Symbol "quote", form] ->
      walk evalUnquotes form
      where evalUnquotes (List [Symbol "unquote", val]) = eval env val
            evalUnquotes val                            = return val

    List (fsym : args) -> do
      (Fn f) <- eval env fsym
      push val
      r <- if isMacro f then
             apply env (fnType f) args >>= eval env
           else
             evalMany env args >>= apply env (fnType f)
      pop
      return r

    _ ->
      return val


evalMany env = traverse (eval env)
evalBody env body = last <$> evalMany env body


evalString, evalFile :: Env -> String -> IO ()
evalString =
  runWithCatch action
  where action env string = do
          readtable <- getReadtable env
          let r = readOne readtable string >>= eval env
          liftIO $ run r >>= either printVal printVal


-- evalWithInfo =
--   runWithCatch action
--   where action env string = do
--           readtable <- getReadtable env
--           result <- readOne readtable string >>= eval env
--           liftIO $ putStrLn $ showVal result ++ " : " ++ show result


evalFile =
  runWithCatch action
  where action env file = do
          readtable <- getReadtable env
          liftIO (readFile file) >>= readMany readtable >>= evalMany env
          return ()


runWithCatch :: (Env -> String -> LispM ()) -> Env -> String -> IO ()
runWithCatch f env x = do
  let action = fromRight' <$> run (f env x)
  catch action (printError :: LispError -> IO ())



{- Apply -}
apply :: Env -> FnType -> [LispVal] -> LispM LispVal
apply env Primitive { purity = p } args =
  case p of
    Pure func ->
      return $ func args
    Impure func ->
      func env args

apply env (Lisp params varargs body closure) args =
  if length params /= length args && not varargs then
    throwWithStack $ NumArgs (length params) (length args)
  else do
    envWithArgs <- bindVars closure $ zipParamsArgs params varargs args
    evalBody envWithArgs body

zipParamsArgs :: [String] -> Bool -> [LispVal] -> [(String, LispVal)]
zipParamsArgs params varargs args =
  if varargs then
    let
      (normalargs, varargs) = splitAt (length params - 1) args
    in
      zip (init params) normalargs ++ [(last params, List varargs)]
  else
    zip params args



{- Fn -}
makeFn :: Bool -> FnName -> [LispVal] -> [LispVal] -> Env -> LispVal
makeFn isMacro name params body env =
  Fn $ FnRecord name isMacro $ Lisp stringParams varargs body env
  where stringParams = filter (/= ".") $ map extractString params
        extractString (Symbol s) = s
        varargs = case drop (length params - 2) params of
          [Symbol ".", Symbol vararg] -> True
          _                           -> False


