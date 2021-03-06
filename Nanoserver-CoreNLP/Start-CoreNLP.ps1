$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$coreNLPDir = $appDir + "\CoreNLP"
$coreNLP = "$env:JAVA_HOME\bin\java.exe"

Set-Location -Path $coreNLPDir
&$coreNLP -mx4g -cp "*" edu.stanford.nlp.pipeline.StanfordCoreNLPServer -port 9000 -timeout 15000