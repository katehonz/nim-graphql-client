import karax / [karax, kdom, vdom]
import ../src/[graphql_client, karax_integration]
import json, strutils, tables

# Примерно Karax приложение с GraphQL клиент

# Глобално състояние на приложението
type
  AppState = ref object
    currentPage: string
    selectedAccountId: int
    createAccountForm: CreateAccountForm
    currentAccountTypeFilter: string
    currentDate: string
    
  CreateAccountForm = object
    code: string
    name: string
    accountType: string
    errors: seq[string]

var appState = AppState(
  currentPage: "accounts",
  selectedAccountId: 0,
  createAccountForm: CreateAccountForm(
    code: "",
    name: "",
    accountType: "ASSET",
    errors: @[]
  ),
  currentAccountTypeFilter: "",
  currentDate: "2024-12-31"
)

# Компонент за навигация
proc NavBar(): VNode =
  buildHtml(nav(class = "navbar")):
    ul:
      li:
        a(href = "#", onclick = proc() = appState.currentPage = "accounts"):
          text "Сметки"
      li:
        a(href = "#", onclick = proc() = appState.currentPage = "trial-balance"):
          text "Оборотна ведомост"
      li:
        a(href = "#", onclick = proc() = appState.currentPage = "create-account"):
          text "Нова сметка"

# Компонент за формата за създаване на сметка
proc CreateAccountForm(): VNode =
  let createAccountMutation = useCreateAccount()
  
  proc handleSubmit() =
    appState.createAccountForm.errors = @[]
    
    # Валидация
    if appState.createAccountForm.code.len < 4:
      appState.createAccountForm.errors.add("Кодът трябва да е поне 4 символа")
    
    if appState.createAccountForm.name.len < 3:
      appState.createAccountForm.errors.add("Името трябва да е поне 3 символа")
    
    if appState.createAccountForm.errors.len > 0:
      redraw()
      return
    
    # Изпълнение на мутацията
    discard createAccountMutation(
      appState.createAccountForm.code,
      appState.createAccountForm.name,
      appState.createAccountForm.accountType
    ).then(proc(result: JsonNode) =
      # Успешно създаване
      appState.createAccountForm = CreateAccountForm(
        code: "",
        name: "",
        accountType: "ASSET",
        errors: @[]
      )
      appState.currentPage = "accounts"
      redraw()
    ).catch(proc(error: cstring) =
      # Грешка при създаване
      appState.createAccountForm.errors.add($error)
      redraw()
    )
  
  result = buildHtml(tdiv(class = "create-account-form")):
    h2: text "Създаване на нова сметка"
    
    if appState.createAccountForm.errors.len > 0:
      tdiv(class = "errors"):
        for error in appState.createAccountForm.errors:
          p(class = "error"): text error
    
    form:
      tdiv(class = "form-group"):
        label(`for` = "account-code"): text "Код на сметката:"
        input(
          `type` = "text",
          id = "account-code",
          value = appState.createAccountForm.code,
          placeholder = "напр. 1100",
          onchange = proc(ev: Event) =
            appState.createAccountForm.code = $ev.target.value
        )
      
      tdiv(class = "form-group"):
        label(`for` = "account-name"): text "Име на сметката:"
        input(
          `type` = "text",
          id = "account-name",
          value = appState.createAccountForm.name,
          placeholder = "напр. Каса",
          onchange = proc(ev: Event) =
            appState.createAccountForm.name = $ev.target.value
        )
      
      tdiv(class = "form-group"):
        label(`for` = "account-type"): text "Тип сметка:"
        select(
          id = "account-type",
          value = appState.createAccountForm.accountType,
          onchange = proc(ev: Event) =
            appState.createAccountForm.accountType = $ev.target.value
        ):
          option(value = "ASSET"): text "Актив"
          option(value = "LIABILITY"): text "Пасив"
          option(value = "EQUITY"): text "Капитал"
          option(value = "INCOME"): text "Приходи"
          option(value = "EXPENSE"): text "Разходи"
      
      tdiv(class = "form-actions"):
        button(
          `type` = "button",
          onclick = handleSubmit
        ):
          text "Създай сметка"
        
        button(
          `type` = "button",
          onclick = proc() = appState.currentPage = "accounts"
        ):
          text "Отказ"

# Подобрен компонент за показване на сметка с детайли
proc AccountDetails(account: JsonNode): VNode =
  let code = account["code"].getStr()
  let name = account["name"].getStr()
  let balance = account["balance"]["amount"].getStr() & " " & account["balance"]["currency"].getStr()
  let accountType = account["accountType"].getStr()
  let isActive = account["isActive"].getBool()
  let createdAt = account["createdAt"].getStr()
  
  # Превод на типа сметка
  let accountTypeText = case accountType:
    of "ASSET": "Актив"
    of "LIABILITY": "Пасив"
    of "EQUITY": "Капитал"
    of "INCOME": "Приходи"
    of "EXPENSE": "Разходи"
    else: accountType
  
  result = buildHtml(tdiv(class = "account-details")):
    tdiv(class = "account-header"):
      h3: text code & " - " & name
      span(class = if isActive: "status active" else: "status inactive"):
        text if isActive: "Активна" else: "Неактивна"
    
    tdiv(class = "account-info"):
      p:
        strong: text "Тип: "
        text accountTypeText
      
      p:
        strong: text "Баланс: "
        span(class = "balance"): text balance
      
      p:
        strong: text "Създадена: "
        text createdAt.split("T")[0]  # Показваме само датата
    
    tdiv(class = "account-actions"):
      button(onclick = proc() = 
        appState.selectedAccountId = account["id"].getInt()
        appState.currentPage = "account-detail"
      ):
        text "Детайли"

# Компонент за списък със сметки с филтриране
proc AccountsPage(): VNode =
  let accountsResult = useAccounts(20, appState.currentAccountTypeFilter)  # Вземаме повече сметки
  
  result = buildHtml(tdiv(class = "accounts-page")):
    h1: text "Сметки"
    
    # Филтри
    tdiv(class = "filters"):
      label: text "Тип сметка: "
      select(onchange = proc(ev: Event) =
        appState.currentAccountTypeFilter = $ev.target.value
        redraw()
      ):
        option(value = ""): text "Всички"
        option(value = "ASSET"): text "Активи"
        option(value = "LIABILITY"): text "Пасиви"
        option(value = "EQUITY"): text "Капитал"
        option(value = "INCOME"): text "Приходи"
        option(value = "EXPENSE"): text "Разходи"
    
    # Съдържание
    renderData(accountsResult.data, accountsResult.loading, accountsResult.error,
      proc(data: JsonNode): VNode =
        let edges = data["accounts"]["edges"]
        let totalCount = data["accounts"]["totalCount"].getInt()
        
        buildHtml(tdiv):
          p: text "Общо сметки: " & $totalCount
          
          tdiv(class = "accounts-grid"):
            for edge in edges:
              AccountDetails(edge["node"])
          
          button(onclick = accountsResult.refetch):
            text "Обнови"
    )

# Компонент за подробности на сметка
proc AccountDetailPage(): VNode =
  let accountResult = useAccount(appState.selectedAccountId)
  
  result = buildHtml(tdiv(class = "account-detail-page")):
    button(
      class = "back-button",
      onclick = proc() = appState.currentPage = "accounts"
    ):
      text "← Назад към сметки"
    
    renderData(accountResult.data, accountResult.loading, accountResult.error,
      proc(data: JsonNode): VNode =
        let account = data["account"]
        
        buildHtml(tdiv):
          AccountDetails(account)
          
          # Допълнителна информация за сметката
          tdiv(class = "account-extended-info"):
            h4: text "Допълнителна информация"
            
            if account.hasKey("parentId") and account["parentId"].kind != JNull:
              p: text "Родителска сметка ID: " & $account["parentId"].getInt()
            
              # Транзакции за сметката
              let transactionsResult = useAccountTransactions(account["id"].getInt())
              
              h4: text "Транзакции"
              
              renderData(transactionsResult.data, transactionsResult.loading, transactionsResult.error,
                proc(data: JsonNode): VNode =
                  let edges = data["accountTransactions"]["edges"]
                  
                  buildHtml(tdiv):
                    if edges.len == 0:
                      p: text "Няма транзакции"
                    
                    for edge in edges:
                      let transaction = edge["node"]
                      let date = transaction["date"].getStr()
                      let description = transaction["description"].getStr()
                      let debit = transaction["debit"]["amount"].getStr() & " " & transaction["debit"]["currency"].getStr()
                      let credit = transaction["credit"]["amount"].getStr() & " " & transaction["credit"]["currency"].getStr()
                      let balanceAfter = transaction["balanceAfter"]["amount"].getStr() & " " & transaction["balanceAfter"]["currency"].getStr()
                      
                      tdiv(class = "transaction-item"):
                        tdiv(class = "transaction-header"):
                          strong: text date
                          span(class = "description"): text description
                        
                        tdiv(class = "transaction-details"):
                          tdiv(class = "transaction-row"):
                            span(class = "label"): text "Дебит:"
                            span(class = "value debit"): text debit
                          
                          tdiv(class = "transaction-row"):
                            span(class = "label"): text "Кредит:"
                            span(class = "value credit"): text credit
                          
                          tdiv(class = "transaction-row"):
                            span(class = "label"): text "Баланс след:"
                            span(class = "value balance"): text balanceAfter
                    
                    button(onclick = transactionsResult.refetch):
                      text "Обнови транзакциите"
    )

# Компонент за оборотна ведомост с подобрения
proc TrialBalancePage(): VNode =
  let balanceResult = useTrialBalance(appState.currentDate)
  
  result = buildHtml(tdiv(class = "trial-balance-page")):
    h1: text "Оборотна ведомост"
    
    # Избор на дата
    tdiv(class = "date-selector"):
      label: text "Дата: "
        input(
          `type` = "date",
          value = appState.currentDate,
          onchange = proc(ev: Event) =
            appState.currentDate = $ev.target.value
            redraw()
        )
    
    renderData(balanceResult.data, balanceResult.loading, balanceResult.error,
      proc(data: JsonNode): VNode =
        let trialBalance = data["trialBalance"]
        let accounts = trialBalance["accounts"]
        let totalDebits = trialBalance["totalDebits"]["amount"].getStr()
        let totalCredits = trialBalance["totalCredits"]["amount"].getStr()
        let isBalanced = trialBalance["isBalanced"].getBool()
        
        buildHtml(tdiv):
          # Резюме
          tdiv(class = "balance-summary"):
            tdiv(class = "summary-item"):
              h3: text "Общо дебит"
              p(class = "amount"): text totalDebits & " лв."
            
            tdiv(class = "summary-item"):
              h3: text "Общо кредит"
              p(class = "amount"): text totalCredits & " лв."
            
            tdiv(class = "summary-item"):
              h3: text "Статус"
              p(class = if isBalanced: "balanced" else: "unbalanced"):
                text if isBalanced: "Балансирана" else: "Небалансирана"
          
          # Таблица с данни
          table(class = "trial-balance-table"):
            thead:
              tr:
                th: text "Код"
                th: text "Име на сметката"
                th: text "Дебит (лв.)"
                th: text "Кредит (лв.)"
            tbody:
              for account in accounts:
                tr:
                  td: text account["accountCode"].getStr()
                  td: text account["accountName"].getStr()
                  td(class = "amount"): text account["debitBalance"]["amount"].getStr()
                  td(class = "amount"): text account["creditBalance"]["amount"].getStr()
          
          # Действия
          tdiv(class = "actions"):
            button(onclick = balanceResult.refetch):
              text "Обнови данни"
            
            button(
              `class` = "export-button",
              onclick = proc() =
                # Експорт на оборотната ведомост като CSV
                let csvData = newStringStream()
                csvData.write("Код,Име,Дебит,Кредит\n")
                
                for account in trialBalance["accounts"]:
                  let code = account["accountCode"].getStr()
                  let name = account["accountName"].getStr()
                  let debit = account["debitBalance"]["amount"].getStr()
                  let credit = account["creditBalance"]["amount"].getStr()
                  
                  csvData.write(code & "," & name & "," & debit & "," & credit & "\n")
                
                # Създаване на CSV файл и изтегляне
                let csvContent = csvData.data
                let blob = newBlob([csvContent], "text/csv;charset=utf-8;")
                let url = URL.createObjectURL(blob)
                
                let a = document.createElement("a")
                a.href = url
                a.download = "оборотна_ведомост_" & appState.currentDate & ".csv"
                document.body.appendChild(a)
                a.click()
                document.body.removeChild(a)
                URL.revokeObjectURL(url)
            ):
              text "Експорт като CSV"
    )

# Главен компонент на приложението
proc App(): VNode =
  result = buildHtml(tdiv(class = "app")):
    NavBar()
    
    main(class = "main-content"):
      case appState.currentPage:
        of "accounts":
          AccountsPage()
        of "trial-balance":
          TrialBalancePage()
        of "create-account":
          CreateAccountForm()
        of "account-detail":
          AccountDetailPage()
        else:
          tdiv: text "Страницата не е намерена"

# CSS стилове
const appStyles = """
.app {
  font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
  max-width: 1200px;
  margin: 0 auto;
  background: #f5f5f5;
  min-height: 100vh;
}

.navbar {
  background: #2c3e50;
  padding: 1rem;
  margin-bottom: 2rem;
}

.navbar ul {
  list-style: none;
  display: flex;
  gap: 2rem;
  margin: 0;
  padding: 0;
}

.navbar a {
  color: white;
  text-decoration: none;
  padding: 0.5rem 1rem;
  border-radius: 4px;
  transition: background-color 0.3s;
}

.navbar a:hover {
  background-color: #34495e;
}

.main-content {
  padding: 0 2rem;
}

.accounts-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
  gap: 1rem;
  margin: 1rem 0;
}

.account-details {
  background: white;
  border-radius: 8px;
  padding: 1rem;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
  transition: transform 0.2s;
}

.account-details:hover {
  transform: translateY(-2px);
  box-shadow: 0 4px 8px rgba(0,0,0,0.15);
}

.account-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
  border-bottom: 1px solid #eee;
  padding-bottom: 0.5rem;
}

.status {
  padding: 0.25rem 0.5rem;
  border-radius: 12px;
  font-size: 0.8rem;
  font-weight: bold;
}

.status.active {
  background: #d4edda;
  color: #155724;
}

.status.inactive {
  background: #f8d7da;
  color: #721c24;
}

.balance {
  font-weight: bold;
  color: #27ae60;
}

.create-account-form {
  background: white;
  border-radius: 8px;
  padding: 2rem;
  max-width: 500px;
  margin: 0 auto;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.form-group {
  margin-bottom: 1rem;
}

.form-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: bold;
}

.form-group input,
.form-group select {
  width: 100%;
  padding: 0.5rem;
  border: 1px solid #ddd;
  border-radius: 4px;
  font-size: 1rem;
}

.form-actions {
  display: flex;
  gap: 1rem;
  justify-content: flex-end;
  margin-top: 2rem;
}

.errors {
  background: #f8d7da;
  border: 1px solid #f5c6cb;
  border-radius: 4px;
  padding: 1rem;
  margin-bottom: 1rem;
}

.error {
  color: #721c24;
  margin: 0.25rem 0;
}

.balance-summary {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 1rem;
  margin: 2rem 0;
}

.summary-item {
  background: white;
  padding: 1.5rem;
  border-radius: 8px;
  text-align: center;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.summary-item h3 {
  margin: 0 0 0.5rem 0;
  color: #2c3e50;
}

.summary-item .amount {
  font-size: 1.5rem;
  font-weight: bold;
  margin: 0;
}

.balanced {
  color: #27ae60;
}

.unbalanced {
  color: #e74c3c;
}

.filters {
  background: white;
  padding: 1rem;
  border-radius: 8px;
  margin-bottom: 1rem;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.date-selector {
  background: white;
  padding: 1rem;
  border-radius: 8px;
  margin-bottom: 1rem;
  box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

.back-button {
  background: #95a5a6;
  color: white;
  border: none;
  padding: 0.5rem 1rem;
  border-radius: 4px;
  cursor: pointer;
  margin-bottom: 1rem;
}

.back-button:hover {
  background: #7f8c8d;
}

.actions {
  margin-top: 2rem;
  text-align: center;
}
"""

# Инициализация на приложението
proc initApp() =
  # Инициализиране на GraphQL контекста
  discard initKaraxGraphQL("http://localhost:8080/accounting/graphql")
  
  # Добавяне на стилове
  injectGraphQLStyles()
  
  # Добавяне на допълнителни стилове
  when defined(js):
    let style = document.createElement("style")
    style.innerHTML = appStyles
    discard document.head.appendChild(style)
  
  # Стартиране на Karax
  setRenderer(App)

# Стартиране на приложението
when isMainModule:
  initApp()
