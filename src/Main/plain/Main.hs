------------------------------------------------------------------------------
-- Copyright 2012-2021, Microsoft Research, Daan Leijen.
--
-- This is free software; you can redistribute it and/or modify it under the
-- terms of the Apache License, Version 2.0. A copy of the License can be
-- found in the LICENSE file at the root of this distribution.
-----------------------------------------------------------------------------
{-
    Main module.
-}
-----------------------------------------------------------------------------
module Main where

import Debug.Trace
import System.Exit            ( exitFailure )
import System.IO              (hPutStrLn, stderr)
import Control.Monad          ( when, foldM )
import Data.List              (intersperse)
import Data.Maybe

import Platform.Config
import Lib.PPrint
import Lib.Printer

import Common.ColorScheme
import Common.Failure         ( catchIO )
import Common.Error
import Common.Name
import Common.File            ( joinPath, getCwd )

import Core.Core              ( coreProgDefs, flattenDefGroups, defType, Def(..) )
import Interpreter.Interpret  ( interpret  )
import Kind.ImportMap         ( importsEmpty )
import Kind.Synonym           ( synonymsIsEmpty, ppSynonyms, synonymsFilter )
import Kind.Assumption        ( kgammaFilter, ppKGamma )
import Type.Assumption        ( ppGamma, ppGammaHidden, gammaFilter, createNameInfoX, gammaNew )
import Type.Pretty            ( ppScheme, Env(context,importsMap,colors), ppName  )

import Compile.Options
import Compile.BuildContext


-- compiled entry
main      = mainArgs ""

-- ghci entry
maing     = maingg ""
maindoc   = maingg "--html"
mainjs    = maingg "--target=js"
maincs    = maingg "--target=cs"

maingg extraOptions
  = mainArgs ("-ilib -itest --verbose " ++ extraOptions)

-- hugs entry
mainh     = mainArgs "-ilib -itest --console=raw"


mainArgs args
  = do (flags,flags0,mode) <- getOptions args
       let with = if (not (null (redirectOutput flags)))
                   then withFileNoColorPrinter (redirectOutput flags)
                   else if (console flags == "html")
                    then withHtmlColorPrinter
                   else if (console flags == "ansi")
                    then withColorPrinter
                    else withNoColorPrinter
       with (mainMode flags flags0 mode)
    `catchIO` \err ->
    do if ("ExitFailure" `isPrefix` err)
        then return ()
        else putStr err
       exitFailure
  where
    isPrefix s t  = (s == take (length s) t)

mainMode :: Flags -> Flags -> Mode -> ColorPrinter -> IO ()
mainMode flags flags0 mode p
  = case mode of
     ModeHelp
      -> showHelp flags p
     ModeVersion
      -> withNoColorPrinter (\monop -> showVersion flags monop)
     ModeCompiler files
      -> do ok <- compileAll p flags files
            when (not ok) $
              do hPutStrLn stderr ("Failed to compile " ++ concat (intersperse "," files))
                 exitFailure
     ModeInteractive files
      -> interpret p flags flags0 files
     ModeLanguageServer files
      -> do hPutStrLn stderr "Language server mode not supported in the plain build of Koka.\n"
            exitFailure

compileAll :: ColorPrinter -> Flags -> [FilePath] -> IO Bool
compileAll p flags fpaths
  = do cwd <- getCwd
       (mbRes,_)  <- runBuildIO (term cwd) flags $
                       do (buildc0,roots) <- buildcAddRootSources fpaths (buildcEmpty flags)
                          let mainEntries = if library flags then []
                                              else map (\rootName -> qualify rootName (newName "main")) roots
                          buildc <- buildcFullBuild (rebuild flags) roots {-force roots always-} mainEntries buildc0
                          buildcThrowOnError
                          mapM_ (compileDone buildc) roots
                          return ()
       return (isJust mbRes)
  where
    term cwd
      = Terminal (putErrorMessage p cwd (showSpan flags) cscheme)
                 (if (verbose flags > 1) then (\msg -> withColor p (colorSource cscheme) (writeLn p msg))
                                         else (\_ -> return ()))
                 (if (verbose flags > 0) then writePrettyLn p else (\_ -> return ()))
                 (writePrettyLn p)

    cscheme
      = colorSchemeFromFlags flags

    putErrorMessage p cwd endToo cscheme err
      = putPrettyLn p (ppErrorMessage cwd endToo cscheme err)

    putPrettyLn p doc
      = do writePrettyLn p doc
           writeLn p ""


compileDone :: BuildContext -> ModuleName -> Build ()
compileDone buildc modname
  = do  flags <- buildcFlags
        -- show (kind) gamma ?
        let defs = buildcGetDefinitions [modname] buildc
        when (showKindSigs flags) $
          do buildcTermInfo $ \penv -> ppKGamma (colors penv) modname (importsMap penv) (defsKGamma defs)
             let syns = defsSynonyms defs
             when (not (synonymsIsEmpty syns)) $
               buildcTermInfo $ \penv -> ppSynonyms penv{context=modname} syns
        when (showTypeSigs flags || showHiddenTypeSigs flags) $
          buildcTermInfo $ \penv -> ppGamma penv{context=modname} (defsGamma defs)
        -- run it?
        when (evaluate flags) $
          case buildcGetMainEntry modname buildc of
            Just (exe,run) -> liftIO $ run
            Nothing        -> addErrorMessageKind ErrBuild (\penv -> text "unable to find main entry point of" <+> ppName penv modname)
        return ()

