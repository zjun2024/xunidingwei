@echo off
rem Double-click this file on Windows. Keep grab_log.py in the same folder.
where py >nul 2>nul
if %errorlevel%==0 (
  py "%~dp0grab_log.py" %*
) else (
  python "%~dp0grab_log.py" %*
)
echo.
pause
