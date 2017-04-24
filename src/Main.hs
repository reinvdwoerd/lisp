module Main where

import           Env
import           Eval
import           System.Console.Repl
import           System.Environment  (getArgs)



main = do
  args <- getArgs
  globalEnv <- newEnv
  case args of
    [file] ->
      evalFile globalEnv file
    [file, "-i"] -> do
      evalFile globalEnv file
      interactive globalEnv
    [] ->
      interactive globalEnv
  where interactive env =
          repl "lisp=> " $ evalString env
