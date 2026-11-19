@echo off
rem Double-click this file on Windows. Keep ios_loc.py in the same folder.
where py >nul 2>nul
if %errorlevel%==0 (
  py "%~dp0ios_loc.py" %*
) else (
  python "%~dp0ios_loc.py" %*
)
echo.
pause
