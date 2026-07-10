@echo off

setlocal

set "SCRIPT_DIR=%~dp0"

pushd "%SCRIPT_DIR%.." >nul



git config core.hooksPath .githooks

if errorlevel 1 (

  echo ERROR: failed to set core.hooksPath

  popd >nul

  exit /b 1

)



echo Configured git hooks for %CD%

echo core.hooksPath=.githooks

echo Installed hooks:

echo - .githooks\pre-commit

echo - .githooks\pre-push



popd >nul

exit /b 0

