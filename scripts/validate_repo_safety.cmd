@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "BASH_EXE="

where bash >nul 2>nul && set "BASH_EXE=bash"
if not defined BASH_EXE if exist "%ProgramFiles%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
if not defined BASH_EXE if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"

if not defined BASH_EXE (
  echo ERROR: Could not find bash. Install Git for Windows or run scripts\validate_repo_safety.sh from a bash shell.
  exit /b 1
)

"%BASH_EXE%" "%SCRIPT_DIR%validate_repo_safety.sh" %*
exit /b %ERRORLEVEL%
