$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$h2oDir = $appDir + "\H2o"
$Java = "$env:JAVA_HOME\bin\java.exe"

Set-Location -Path $h2oDir
&$Java -jar h2o.jar