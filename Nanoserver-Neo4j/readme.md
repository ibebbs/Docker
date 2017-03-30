# A Docker container of Neo4j Community 3.1.3 running on Windows NanoServer

## Building 
From powershell run ```.\build.ps1```

## Running
From a command prompt ```docker run -it --rm --expose=7473 --expose=7687 -p 7474:7474 -p 7473:7473 -p 7687:7687 ibebbs/nanoneo:latest```