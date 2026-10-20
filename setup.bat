@echo off
REM ---------------------------------------------------------------------------
REM PaintPro Billing - one-time project setup (Windows 10 / 11)
REM
REM Generates the Windows runner for your installed Flutter version, then
REM fetches packages. Your source in lib\ and test\ is never touched.
REM ---------------------------------------------------------------------------
setlocal enabledelayedexpansion
cd /d "%~dp0"

where flutter >nul 2>nul
if errorlevel 1 (
  echo Flutter was not found on PATH.
  echo Install it from https://docs.flutter.dev/get-started/install/windows
  exit /b 1
)

echo ==^> Flutter version
call flutter --version

echo ==^> Enabling Windows desktop support
call flutter config --enable-windows-desktop >nul

set "STASH=%TEMP%\paintpro_stash_%RANDOM%"
echo ==^> Protecting sources in %STASH%
mkdir "%STASH%"
xcopy /E /I /Q /Y lib "%STASH%\lib" >nul
if exist test xcopy /E /I /Q /Y test "%STASH%\test" >nul
if exist docs xcopy /E /I /Q /Y docs "%STASH%\docs" >nul
if exist README.md copy /Y README.md "%STASH%\README.md" >nul
copy /Y pubspec.yaml "%STASH%\pubspec.yaml" >nul
copy /Y analysis_options.yaml "%STASH%\analysis_options.yaml" >nul

echo ==^> Generating the Windows runner
call flutter create --project-name paint_billing --org com.paintpro --platforms=windows --overwrite . >nul

echo ==^> Restoring sources
rmdir /S /Q lib
xcopy /E /I /Q /Y "%STASH%\lib" lib >nul
if exist "%STASH%\test" ( rmdir /S /Q test & xcopy /E /I /Q /Y "%STASH%\test" test >nul )
if exist "%STASH%\docs" ( rmdir /S /Q docs & xcopy /E /I /Q /Y "%STASH%\docs" docs >nul )
if exist "%STASH%\README.md" copy /Y "%STASH%\README.md" README.md >nul
copy /Y "%STASH%\pubspec.yaml" pubspec.yaml >nul
copy /Y "%STASH%\analysis_options.yaml" analysis_options.yaml >nul
rmdir /S /Q "%STASH%"

echo ==^> Fetching packages
call flutter pub get

echo ==^> Analysing
call flutter analyze

echo ==^> Running tests
call flutter test

echo.
echo Setup complete.
echo.
echo   Run in debug    :  flutter run -d windows
echo   Build a release :  flutter build windows --release
echo   Output folder   :  build\windows\x64\runner\Release\
echo.
echo   First sign-in   :  admin / admin123  (change it in Settings ^> Users)
echo.
endlocal
