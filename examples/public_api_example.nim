import ../src/graphql_client
import asyncdispatch, json, tables

# Пример с публични GraphQL API-та

proc testCountriesAPI() {.async.} =
  echo "=== Countries GraphQL API Test ==="
  echo "Using: https://countries.trevorblades.com/graphql"
  echo ""
  
  let client = newGraphQLClient("https://countries.trevorblades.com/graphql")
  
  # 1. Получаване на списък с континенти
  echo "1. Getting continents list..."
  let continentsQuery = """
    query GetContinents {
      continents {
        code
        name
      }
    }
  """
  
  let continentsReq = newGraphQLRequest(continentsQuery)
  let continentsResp = await client.execute(continentsReq)
  
  if continentsResp.isSuccess():
    echo "Continents found:"
    for continent in continentsResp.data["continents"]:
      echo "  - ", continent["name"].getStr(), " (", continent["code"].getStr(), ")"
  else:
    echo "Error: ", continentsResp.errors[0].msg
  
  # 2. Получаване на държави от Европа
  echo "\n2. Getting European countries..."
  let countriesQuery = """
    query GetEuropeanCountries {
      continent(code: "EU") {
        name
        countries {
          code
          name
          capital
          currency
          languages {
            name
          }
        }
      }
    }
  """
  
  let countriesReq = newGraphQLRequest(countriesQuery)
  let countriesResp = await client.execute(countriesReq)
  
  if countriesResp.isSuccess():
    let europe = countriesResp.data["continent"]
    echo "Countries in ", europe["name"].getStr(), ":"
    
    var count = 0
    for country in europe["countries"]:
      if count < 5:  # Показваме само първите 5
        echo "  - ", country["name"].getStr()
        echo "    Capital: ", country["capital"].getStr()
        echo "    Currency: ", country["currency"].getStr()
        if country["languages"].len > 0:
          echo "    Language: ", country["languages"][0]["name"].getStr()
        count += 1
    
    echo "  ... and ", europe["countries"].len - 5, " more countries"
  
  # 3. Търсене на конкретна държава
  echo "\n3. Searching for Bulgaria..."
  let countryQuery = """
    query GetCountry($code: ID!) {
      country(code: $code) {
        name
        native
        capital
        emoji
        currency
        languages {
          name
          native
        }
        continent {
          name
        }
      }
    }
  """
  
  let variables = %* {"code": "BG"}
  let countryReq = newGraphQLRequest(countryQuery, variables)
  let countryResp = await client.execute(countryReq)
  
  if countryResp.isSuccess():
    let country = countryResp.data["country"]
    echo "Found country:"
    echo "  Name: ", country["name"].getStr(), " (", country["native"].getStr(), ")"
    echo "  Flag: ", country["emoji"].getStr()
    echo "  Capital: ", country["capital"].getStr()
    echo "  Currency: ", country["currency"].getStr()
    echo "  Continent: ", country["continent"]["name"].getStr()
    echo "  Languages:"
    for lang in country["languages"]:
      echo "    - ", lang["name"].getStr(), " (", lang["native"].getStr(), ")"
  
  client.close()

proc testSpaceXAPI() {.async.} =
  echo "\n=== SpaceX GraphQL API Test ==="
  echo "Using: https://spacex-production.up.railway.app/"
  echo ""
  
  let client = newGraphQLClient("https://spacex-production.up.railway.app/")
  
  # 1. Информация за компанията
  echo "1. Getting company info..."
  let companyQuery = """
    query GetCompanyInfo {
      company {
        name
        founder
        founded
        employees
        ceo
        summary
      }
    }
  """
  
  let companyReq = newGraphQLRequest(companyQuery)
  let companyResp = await client.execute(companyReq)
  
  if companyResp.isSuccess():
    let company = companyResp.data["company"]
    echo "Company: ", company["name"].getStr()
    echo "  Founded: ", company["founded"].getInt(), " by ", company["founder"].getStr()
    echo "  CEO: ", company["ceo"].getStr()
    echo "  Employees: ", company["employees"].getInt()
    echo "  Summary: ", company["summary"].getStr().substr(0, 100), "..."
  
  # 2. Последни изстрелвания
  echo "\n2. Getting latest launches..."
  let launchesQuery = """
    query GetLatestLaunches {
      launchesPast(limit: 5) {
        mission_name
        launch_date_local
        launch_success
        rocket {
          rocket_name
        }
        launch_site {
          site_name
        }
      }
    }
  """
  
  let launchesReq = newGraphQLRequest(launchesQuery)
  let launchesResp = await client.execute(launchesReq)
  
  if launchesResp.isSuccess():
    echo "Latest launches:"
    for launch in launchesResp.data["launchesPast"]:
      echo "  - ", launch["mission_name"].getStr()
      echo "    Date: ", launch["launch_date_local"].getStr()
      echo "    Rocket: ", launch["rocket"]["rocket_name"].getStr()
      echo "    Site: ", launch["launch_site"]["site_name"].getStr()
      let success = if launch["launch_success"].kind == JBool: 
                      if launch["launch_success"].getBool(): "✓ Success" else: "✗ Failed"
                    else: "? Unknown"
      echo "    Status: ", success
  
  client.close()

proc testRickAndMortyAPI() {.async.} =
  echo "\n=== Rick and Morty GraphQL API Test ==="
  echo "Using: https://rickandmortyapi.com/graphql"
  echo ""
  
  let client = newGraphQLClient("https://rickandmortyapi.com/graphql")
  
  # Търсене на персонажи
  echo "1. Searching for characters..."
  let charactersQuery = """
    query GetCharacters($name: String!) {
      characters(filter: { name: $name }) {
        results {
          id
          name
          status
          species
          gender
          origin {
            name
          }
          location {
            name
          }
          episode {
            name
            episode
          }
        }
      }
    }
  """
  
  let variables = %* {"name": "Rick"}
  let charactersReq = newGraphQLRequest(charactersQuery, variables)
  let charactersResp = await client.execute(charactersReq)
  
  if charactersResp.isSuccess():
    echo "Characters with 'Rick' in name:"
    let results = charactersResp.data["characters"]["results"]
    
    for i in 0..<results.len:
      if i < 3:  # Показваме първите 3
        let character = results[i]
        echo "  - ", character["name"].getStr()
        echo "    Status: ", character["status"].getStr()
        echo "    Species: ", character["species"].getStr()
        echo "    Origin: ", character["origin"]["name"].getStr()
        echo "    Location: ", character["location"]["name"].getStr()
        echo "    Episodes: ", character["episode"].len
  
  client.close()

# Главна функция
proc main() {.async.} =
  try:
    await testCountriesAPI()
    await testSpaceXAPI()
    await testRickAndMortyAPI()
    
    echo "\n=== All tests completed successfully! ==="
  except Exception as e:
    echo "Error: ", e.msg

when isMainModule:
  echo "GraphQL Client - Public API Examples"
  echo "===================================="
  echo ""
  
  waitFor main()