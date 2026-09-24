@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Purpose: dispatch the adjacent Linux test runner to one named WSL as root.
rem Usage: tools\make-test.cmd --wsl DISTRO
rem Path: derive /mnt/<lowercase drive>/.../tools/make-test.sh from this file,
rem never from the current working directory. Drive-letter paths only.
rem No confirmation bypass: make-test.sh reads both default-No prompts.
rem Environment: no configuration variables. Requires Windows PowerShell and WSL.
rem Return the Linux exit code unchanged; invalid arguments/path return 2.
if /I "%~1"=="--help" goto help
if /I not "%~1"=="--wsl" goto usage_error
if "%~2"=="" goto usage_error
if not "%~3"=="" goto usage_error
set "win_script=%~dp0make-test.sh"
if not exist "%win_script%" (
    echo ERROR: adjacent make-test.sh was not found. 1>&2
    exit /b 2
)
if not "%win_script:~1,1%"==":" (
    echo ERROR: use a Windows drive-letter checkout; UNC paths are not supported. 1>&2
    exit /b 2
)
set "drive=%win_script:~0,1%"
for %%D in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do if /I "%drive%"=="%%D" set "drive=%%D"
set "relative_script=%win_script:~2%"
set "wsl_script=/mnt/%drive%%relative_script:\=/%"
set "PGCC_CMD_DISTRO=%~2"
set "PGCC_CMD_SCRIPT=%wsl_script%"
rem Pass values as data, not interpolated PowerShell/Bash source code.
powershell.exe -NoLogo -NoProfile -Command "& wsl.exe --distribution $env:PGCC_CMD_DISTRO --user root --exec bash $env:PGCC_CMD_SCRIPT --local; exit $LASTEXITCODE"
exit /b %errorlevel%

:usage_error
echo ERROR: expected --wsl DISTRO with no additional arguments. 1>&2
echo Usage: tools\make-test.cmd --wsl DISTRO 1>&2
exit /b 2

:help
echo Usage: tools\make-test.cmd --wsl DISTRO
echo Automatically maps this script's Windows drive path through /mnt.
echo The target runner asks for test and destructive-run permission separately.
exit /b 0
