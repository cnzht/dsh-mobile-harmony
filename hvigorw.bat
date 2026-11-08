@echo off
rem Portable HAP build entry for this project.
rem Resolves DevEco Studio from DEVECO_HOME, else DEVECO_SDK_HOME's parent, else common paths.
rem Usage: hvigorw.bat --mode module -p product=default -p module=entry@default assembleHap
setlocal

set "IDE="
if defined DEVECO_HOME if exist "%DEVECO_HOME%\tools\hvigor\bin\hvigorw.js" set "IDE=%DEVECO_HOME%"
if not defined IDE if defined DEVECO_SDK_HOME if exist "%DEVECO_SDK_HOME%\..\tools\hvigor\bin\hvigorw.js" set "IDE=%DEVECO_SDK_HOME%\.."
if not defined IDE if exist "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" set "IDE=C:\Program Files\Huawei\DevEco Studio"
if not defined IDE if exist "D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.js" set "IDE=D:\Program Files\Huawei\DevEco Studio"
if not defined IDE (
  echo [hvigorw] DevEco Studio not found. Set DEVECO_HOME to your DevEco Studio directory.
  echo [hvigorw] e.g. set DEVECO_HOME=C:\Program Files\Huawei\DevEco Studio
  exit /b 1
)

set "DEVECO_SDK_HOME=%IDE%\sdk"
if not defined JAVA_HOME set "JAVA_HOME=%IDE%\jbr"
set "PATH=%IDE%\jbr\bin;%IDE%\tools\node;%IDE%\tools\ohpm\bin;%PATH%"

"%IDE%\tools\node\node.exe" "%IDE%\tools\hvigor\bin\hvigorw.js" %*
exit /b %errorlevel%
