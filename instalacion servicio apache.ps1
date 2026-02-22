# 1. Configuración de rutas
$apacheBin = "C:\HSLS-14.2\Apache\bin"
$serviceName = "HSLS14.2"
$maxRetries = 10


Write-Host "`n[5/5] Proceso finalizado."
At line:48 char:35
+         Write-Host "    - Intento $i: Puerto 443 ocupado por PID $pid ...
+                                   ~~~
Variable reference is not valid. ':' was not followed by a valid variable name character. Consider using ${} to delimit the name.
At line:76 char:38
+         if ($c) { Write-Host "Puerto $_: OCUPADO por PID $($c.OwningP ...
+                                      ~~~
Variable reference is not valid. ':' was not followed by a valid variable name character. Consider using ${} to delimit the name.
At line:77 char:35
+         else { Write-Host "Puerto $_: LIBRE" -ForegroundColor Green }
+                                   ~~~
Variable reference is not valid. ':' was not followed by a valid variable name character. Consider using ${} to delimit the name.
    + CategoryInfo          : ParserError: (:) [], ParentContainsErrorRecordException
    + FullyQualifiedErrorId : InvalidVariableReferenceWithDrive
