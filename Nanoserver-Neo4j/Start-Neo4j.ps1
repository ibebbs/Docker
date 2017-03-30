$targetDir = "C:\"
$appDir = $targetDir + "\Apps"
$dataDir = $targetDir + "\Data"
$neo4jDir = $appDir + "\Neo4j"
$neo4jDataDir = $dataDir + "\Neo4j"
$neo4j = $neo4jDir + "\bin\neo4j.bat"

Set-Location -Path $neo4jDir
&$neo4j console