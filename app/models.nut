local GLib = import("GLib")

function table_get(t, key, fallback = null) {
    if (t != null && key in t) return t[key]
    return fallback
}

function as_float(value, fallback = 0.0) {
    if (value == null) return fallback
    try {
        return value.tofloat()
    } catch (e) {
        return fallback
    }
}

function as_int(value, fallback = 0) {
    if (value == null) return fallback
    try {
        return value.tointeger()
    } catch (e) {
        return fallback
    }
}

function parse_iso_date(text) {
    if (text == null || text.len() < 10) return null
    try {
        return {
            year = text.slice(0, 4).tointeger(),
            month = text.slice(5, 7).tointeger(),
            day = text.slice(8, 10).tointeger()
        }
    } catch (e) {
        return null
    }
}

function date_from_iso(text) {
    local parts = parse_iso_date(text)
    if (parts == null) return null
    local utc = GLib.TimeZone.new_utc()
    return GLib.DateTime.new(utc, parts.year, parts.month, parts.day, 0, 0, 0.0)
}

function format_period_label(start_dt, end_dt) {
    return start_dt.format("%-d %b %Y") + " - " + end_dt.format("%-d %b %Y")
}

class TransactionSplit {
    folder_id = ""
    envelope_id = ""
    description = ""
    amount = 0.0

    constructor(folder_id = "", envelope_id = "", description = "", amount = 0.0) {
        this.folder_id = folder_id
        this.envelope_id = envelope_id
        this.description = description
        this.amount = as_float(amount)
    }

    function to_table() {
        return {
            folder_id = this.folder_id,
            envelope_id = this.envelope_id,
            description = this.description,
            amount = this.amount
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

class Account {
    id = ""
    name = ""
    number = ""
    description = ""
    balance = 0.0

    constructor(id = "", name = "", number = "", balance = 0.0, description = "") {
        this.id = id
        this.name = name
        this.number = number
        this.balance = as_float(balance)
        this.description = description
    }

    function to_table() {
        return {
            id = this.id,
            name = this.name,
            number = this.number,
            description = this.description,
            balance = this.balance
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

class Envelope {
    id = ""
    name = ""
    description = ""
    hidden = false

    constructor(id = "", name = "", description = "", hidden = false) {
        this.id = id
        this.name = name
        this.description = description
        this.hidden = hidden
    }

    function to_table() {
        return {
            id = this.id,
            name = this.name,
            description = this.description,
            hidden = this.hidden
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

class EnvelopeFolder {
    id = ""
    name = ""
    type = "expense"
    hidden = false
    envelopes = null

    constructor(id = "", name = "", type = "expense", hidden = false) {
        this.id = id
        this.name = name
        this.type = type
        this.hidden = hidden
        this.envelopes = []
    }

    function add_envelope(envelope) {
        this.envelopes.push(envelope)
    }

    function to_table() {
        local envelope_rows = []
        foreach (envelope in this.envelopes) envelope_rows.push(envelope.to_table())
        return {
            id = this.id,
            name = this.name,
            type = this.type,
            hidden = this.hidden,
            envelopes = envelope_rows
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

class ImportRule {
    id = ""
    name = ""
    pattern = ""
    type = "expense"
    folder_id = ""
    envelope_id = ""
    priority = 100
    enabled = true

    constructor(id = "", name = "", pattern = "", type = "expense",
                folder_id = "", envelope_id = "", priority = 100, enabled = true) {
        this.id = id
        this.name = name
        this.pattern = pattern
        this.type = type
        this.folder_id = folder_id
        this.envelope_id = envelope_id
        this.priority = as_int(priority, 100)
        this.enabled = enabled
    }

    function to_table() {
        return {
            id = this.id,
            name = this.name,
            pattern = this.pattern,
            type = this.type,
            folder_id = this.folder_id,
            envelope_id = this.envelope_id,
            priority = this.priority,
            enabled = this.enabled
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

class Transaction {
    id = ""
    account_id = ""
    date = ""
    type = "expense"
    folder_id = ""
    envelope_id = ""
    description = ""
    amount = 0.0
    transfer_account_id = ""
    splits = null

    constructor(id = "", account_id = "", date = "", type = "expense",
                folder_id = "", envelope_id = "", description = "",
                amount = 0.0, transfer_account_id = "", splits = null) {
        this.id = id
        this.account_id = account_id
        this.date = date
        this.type = type
        this.folder_id = folder_id
        this.envelope_id = envelope_id
        this.description = description
        this.amount = as_float(amount)
        this.transfer_account_id = transfer_account_id
        this.splits = splits == null ? [] : splits
    }

    function affects_account(account_id) {
        return this.account_id == account_id ||
            (this.type == "transfer" && this.transfer_account_id == account_id)
    }

    function signed_amount_for(account_id) {
        if (this.type == "income" && this.account_id == account_id) return this.amount
        if (this.type == "expense" && this.account_id == account_id) return -this.amount
        if (this.type == "transfer" && this.account_id == account_id) return -this.amount
        if (this.type == "transfer" && this.transfer_account_id == account_id) return this.amount
        return 0.0
    }

    function split_total() {
        local total = 0.0
        foreach (split in this.splits) total = total + split.amount
        return total
    }

    function to_table() {
        local split_rows = []
        foreach (split in this.splits) split_rows.push(split.to_table())
        return {
            id = this.id,
            account_id = this.account_id,
            date = this.date,
            type = this.type,
            folder_id = this.folder_id,
            envelope_id = this.envelope_id,
            description = this.description,
            amount = this.amount,
            transfer_account_id = this.transfer_account_id,
            splits = split_rows
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

class BudgetEnvelope {
    id = ""
    name = ""
    budgeted = 0.0
    spent = 0.0
    type = "expense"
    folder_id = ""
    envelope_id = ""
    period = ""

    constructor(id = "", name = "", budgeted = 0.0, spent = 0.0,
                type = "expense", folder_id = "", envelope_id = "", period = "") {
        this.id = id
        this.name = name
        this.budgeted = as_float(budgeted)
        this.spent = as_float(spent)
        this.type = type
        this.folder_id = folder_id
        this.envelope_id = envelope_id
        this.period = period
    }

    function remaining(spent_value = null) {
        local actual_spent = spent_value == null ? this.spent : as_float(spent_value)
        return this.budgeted - actual_spent
    }

    function to_table() {
        return {
            id = this.id,
            name = this.name,
            budgeted = this.budgeted,
            spent = this.spent,
            type = this.type,
            folder_id = this.folder_id,
            envelope_id = this.envelope_id,
            period = this.period
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

class DoughDocument {
    title = "Household Budget"
    currency = "$"
    period_index = 0
    periods = null
    period_length = "monthly"
    start_date = "2026-06-01"
    date_format = "DD/MM/YYYY"
    reserve_enabled = false
    reserve_amount = 0.0
    accounts = null
    income_folders = null
    expense_folders = null
    transactions = null
    budgets = null
    import_rules = null

    constructor() {
        this.periods = [
            "1 Jun 2026 - 30 Jun 2026",
            "1 Jul 2026 - 31 Jul 2026",
            "1 Aug 2026 - 31 Aug 2026"
        ]
        this.accounts = []
        this.income_folders = []
        this.expense_folders = []
        this.transactions = []
        this.budgets = []
        this.import_rules = []
    }

    function current_period() {
        if (this.periods.len() == 0) this.regenerate_periods()
        if (this.periods.len() == 0) return ""
        if (this.period_index < 0) this.period_index = 0
        if (this.period_index >= this.periods.len()) this.period_index = this.periods.len() - 1
        return this.periods[this.period_index]
    }

    function regenerate_periods(count = 12) {
        local start = date_from_iso(this.start_date)
        if (start == null) return

        local generated = []
        local current = start
        for (local i = 0; i < count; i = i + 1) {
            local next = null
            if (this.period_length == "weekly") next = current.add_days(7)
            else if (this.period_length == "fortnightly") next = current.add_days(14)
            else next = current.add_months(1)

            local end_dt = next.add_days(-1)
            generated.push(format_period_label(current, end_dt))
            current = next
        }
        this.periods = generated
        if (this.period_index >= this.periods.len()) this.period_index = this.periods.len() - 1
        if (this.period_index < 0) this.period_index = 0
    }

    function add_account(account) {
        this.accounts.push(account)
    }

    function add_income_folder(folder) {
        folder.type = "income"
        this.income_folders.push(folder)
    }

    function add_expense_folder(folder) {
        folder.type = "expense"
        this.expense_folders.push(folder)
    }

    function add_transaction(transaction) {
        this.transactions.push(transaction)
    }

    function add_budget(envelope) {
        if (envelope.period == "") envelope.period = this.current_period()
        this.budgets.push(envelope)
    }

    function add_import_rule(rule) {
        this.import_rules.push(rule)
    }

    function folders_for_type(type) {
        return type == "income" ? this.income_folders : this.expense_folders
    }

    function find_account(id) {
        foreach (account in this.accounts)
            if (account.id == id) return account
        return null
    }

    function find_folder(type, folder_id) {
        foreach (folder in this.folders_for_type(type))
            if (folder.id == folder_id) return folder
        return null
    }

    function find_envelope(type, folder_id, envelope_id) {
        local folder = this.find_folder(type, folder_id)
        if (folder == null) return null
        foreach (envelope in folder.envelopes)
            if (envelope.id == envelope_id) return envelope
        return null
    }

    function folder_label(type, folder_id) {
        local folder = this.find_folder(type, folder_id)
        return folder == null ? "" : folder.name
    }

    function envelope_label(type, folder_id, envelope_id, fallback = "") {
        local envelope = this.find_envelope(type, folder_id, envelope_id)
        return envelope == null ? fallback : envelope.name
    }

    function transactions_for_account(account_id) {
        local out = []
        foreach (transaction in this.transactions)
            if (transaction.affects_account(account_id)) out.push(transaction)
        return out
    }

    function account_balance(account) {
        local balance = account.balance
        foreach (transaction in this.transactions)
            balance = balance + transaction.signed_amount_for(account.id)
        return balance
    }

    function budget_spent(budget) {
        local total = 0.0
        foreach (transaction in this.transactions) {
            if (transaction.type != budget.type) continue

            if (transaction.splits.len() > 0) {
                foreach (split in transaction.splits) {
                    if (split.folder_id == budget.folder_id &&
                        split.envelope_id == budget.envelope_id)
                        total = total + split.amount
                }
            } else if (transaction.folder_id == budget.folder_id &&
                       transaction.envelope_id == budget.envelope_id) {
                total = total + transaction.amount
            }
        }
        return total == 0.0 ? budget.spent : total
    }

    function budget_name(budget) {
        return this.envelope_label(budget.type, budget.folder_id, budget.envelope_id, budget.name)
    }

    function total_budgeted(type = null) {
        local total = 0.0
        foreach (budget in this.budgets)
            if (type == null || budget.type == type) total = total + budget.budgeted
        return total
    }

    function total_spent(type = null) {
        local total = 0.0
        foreach (budget in this.budgets)
            if (type == null || budget.type == type) total = total + this.budget_spent(budget)
        return total
    }

    function unallocated_amount() {
        local reserve = this.reserve_enabled ? this.reserve_amount : 0.0
        return this.total_budgeted("income") - this.total_budgeted("expense") - reserve
    }

    function to_table() {
        local account_rows = []
        foreach (account in this.accounts) account_rows.push(account.to_table())

        local income_folder_rows = []
        foreach (folder in this.income_folders) income_folder_rows.push(folder.to_table())

        local expense_folder_rows = []
        foreach (folder in this.expense_folders) expense_folder_rows.push(folder.to_table())

        local transaction_rows = []
        foreach (transaction in this.transactions) transaction_rows.push(transaction.to_table())

        local budget_rows = []
        foreach (budget in this.budgets) budget_rows.push(budget.to_table())

        local import_rule_rows = []
        foreach (rule in this.import_rules) import_rule_rows.push(rule.to_table())

        return {
            schema = 3,
            title = this.title,
            currency = this.currency,
            period_index = this.period_index,
            periods = this.periods,
            period_length = this.period_length,
            start_date = this.start_date,
            date_format = this.date_format,
            reserve_enabled = this.reserve_enabled,
            reserve_amount = this.reserve_amount,
            accounts = account_rows,
            income_folders = income_folder_rows,
            expense_folders = expense_folder_rows,
            transactions = transaction_rows,
            budgets = budget_rows,
            import_rules = import_rule_rows
        }
    }

    function _tojson() {
        return this.to_table()
    }
}

function account_from_table(t) {
    return Account(
        table_get(t, "id", ""),
        table_get(t, "name", ""),
        table_get(t, "number", ""),
        table_get(t, "balance", 0.0),
        table_get(t, "description", ""))
}

function envelope_from_table(t) {
    return Envelope(
        table_get(t, "id", ""),
        table_get(t, "name", ""),
        table_get(t, "description", ""),
        table_get(t, "hidden", false))
}

function folder_from_table(t, fallback_type) {
    local folder = EnvelopeFolder(
        table_get(t, "id", ""),
        table_get(t, "name", ""),
        table_get(t, "type", fallback_type),
        table_get(t, "hidden", false))
    foreach (row in table_get(t, "envelopes", []))
        folder.add_envelope(envelope_from_table(row))
    return folder
}

function import_rule_from_table(t) {
    return ImportRule(
        table_get(t, "id", ""),
        table_get(t, "name", ""),
        table_get(t, "pattern", ""),
        table_get(t, "type", "expense"),
        table_get(t, "folder_id", ""),
        table_get(t, "envelope_id", ""),
        table_get(t, "priority", 100),
        table_get(t, "enabled", true))
}

function transaction_from_table(t) {
    local splits = []
    foreach (row in table_get(t, "splits", []))
        splits.push(split_from_table(row))

    return Transaction(
        table_get(t, "id", ""),
        table_get(t, "account_id", ""),
        table_get(t, "date", ""),
        table_get(t, "type", "expense"),
        table_get(t, "folder_id", ""),
        table_get(t, "envelope_id", ""),
        table_get(t, "description", ""),
        table_get(t, "amount", 0.0),
        table_get(t, "transfer_account_id", ""),
        splits)
}

function split_from_table(t) {
    return TransactionSplit(
        table_get(t, "folder_id", ""),
        table_get(t, "envelope_id", ""),
        table_get(t, "description", ""),
        table_get(t, "amount", 0.0))
}

function budget_from_table(t) {
    return BudgetEnvelope(
        table_get(t, "id", ""),
        table_get(t, "name", table_get(t, "envelope", "")),
        table_get(t, "budgeted", 0.0),
        table_get(t, "spent", 0.0),
        table_get(t, "type", "expense"),
        table_get(t, "folder_id", ""),
        table_get(t, "envelope_id", ""),
        table_get(t, "period", ""))
}

function ensure_default_folders(doc) {
    if (doc.income_folders.len() == 0) {
        local income = EnvelopeFolder("income-main", "Income", "income")
        income.add_envelope(Envelope("salary", "Salary", "Regular income"))
        income.add_envelope(Envelope("interest", "Interest", "Interest and investment income"))
        doc.add_income_folder(income)
    }

    if (doc.expense_folders.len() == 0) {
        local household = EnvelopeFolder("expense-household", "Household", "expense")
        household.add_envelope(Envelope("groceries", "Groceries", "Food and household supplies"))
        household.add_envelope(Envelope("utilities", "Utilities", "Power, water, internet"))
        household.add_envelope(Envelope("transport", "Transport", "Fuel, public transport, maintenance"))
        household.add_envelope(Envelope("eating-out", "Eating Out", "Restaurants and take-away"))
        doc.add_expense_folder(household)
    }
}

function ensure_default_import_rules(doc) {
    if (doc.import_rules.len() > 0) return
    ensure_default_folders(doc)

    doc.add_import_rule(ImportRule(
        "rule-groceries",
        "Groceries",
        "(?i)(grocery|groceries|supermarket|coles|woolworths|aldi|iga)",
        "expense",
        "expense-household",
        "groceries",
        10))

    doc.add_import_rule(ImportRule(
        "rule-utilities",
        "Utilities",
        "(?i)(electric|power|energy|water|internet|telstra|optus|utility|utilities)",
        "expense",
        "expense-household",
        "utilities",
        20))

    doc.add_import_rule(ImportRule(
        "rule-transport",
        "Transport",
        "(?i)(fuel|petrol|diesel|transport|train|bus|uber|taxi|parking)",
        "expense",
        "expense-household",
        "transport",
        30))

    doc.add_import_rule(ImportRule(
        "rule-eating-out",
        "Eating Out",
        "(?i)(restaurant|cafe|coffee|take.?away|ubereats|doordash|menulog)",
        "expense",
        "expense-household",
        "eating-out",
        40))

    doc.add_import_rule(ImportRule(
        "rule-salary",
        "Salary",
        "(?i)(salary|payroll|wages|pay deposit)",
        "income",
        "income-main",
        "salary",
        10))

    doc.add_import_rule(ImportRule(
        "rule-interest",
        "Interest",
        "(?i)(interest)",
        "income",
        "income-main",
        "interest",
        20))
}

function migrate_simple_budgets(doc) {
    local needs_migration = false
    foreach (budget in doc.budgets) {
        if (budget.folder_id == "" || budget.envelope_id == "")
            needs_migration = true
    }
    if (!needs_migration) return

    ensure_default_folders(doc)
    foreach (budget in doc.budgets) {
        if (budget.folder_id != "" && budget.envelope_id != "") continue

        local folder = doc.expense_folders[0]
        local normalized = budget.name.tolower()
        local matched = null
        foreach (envelope in folder.envelopes) {
            if (envelope.name.tolower() == normalized) matched = envelope
        }

        if (matched == null) {
            local eid = "env-" + normalized
            matched = Envelope(eid, budget.name, "")
            folder.add_envelope(matched)
        }

        budget.type = "expense"
        budget.folder_id = folder.id
        budget.envelope_id = matched.id
    }
}

function document_from_table(t) {
    local doc = DoughDocument()
    doc.title = table_get(t, "title", doc.title)
    doc.currency = table_get(t, "currency", doc.currency)
    doc.period_index = as_int(table_get(t, "period_index", 0), 0)
    doc.periods = table_get(t, "periods", doc.periods)
    doc.period_length = table_get(t, "period_length", doc.period_length)
    doc.start_date = table_get(t, "start_date", doc.start_date)
    doc.date_format = table_get(t, "date_format", doc.date_format)
    doc.reserve_enabled = table_get(t, "reserve_enabled", doc.reserve_enabled)
    doc.reserve_amount = as_float(table_get(t, "reserve_amount", doc.reserve_amount))

    doc.accounts = []
    foreach (row in table_get(t, "accounts", []))
        doc.add_account(account_from_table(row))

    doc.income_folders = []
    foreach (row in table_get(t, "income_folders", []))
        doc.add_income_folder(folder_from_table(row, "income"))

    doc.expense_folders = []
    foreach (row in table_get(t, "expense_folders", []))
        doc.add_expense_folder(folder_from_table(row, "expense"))

    doc.transactions = []
    foreach (row in table_get(t, "transactions", []))
        doc.add_transaction(transaction_from_table(row))

    doc.budgets = []
    foreach (row in table_get(t, "budgets", []))
        doc.add_budget(budget_from_table(row))

    doc.import_rules = []
    foreach (row in table_get(t, "import_rules", []))
        doc.add_import_rule(import_rule_from_table(row))

    migrate_simple_budgets(doc)
    if (!("import_rules" in t)) ensure_default_import_rules(doc)
    return doc
}

function sample_document() {
    local doc = DoughDocument()
    doc.add_account(Account("everyday", "Everyday", "1001", 2450.00, "Main transaction account"))
    doc.add_account(Account("savings", "Savings", "2001", 8150.00, "Emergency fund"))
    doc.add_account(Account("credit-card", "Credit Card", "3001", -360.50, "Monthly card"))

    ensure_default_folders(doc)
    doc.add_budget(BudgetEnvelope("budget-groceries", "Groceries", 900.00, 0.0, "expense", "expense-household", "groceries"))
    doc.add_budget(BudgetEnvelope("budget-utilities", "Utilities", 420.00, 0.0, "expense", "expense-household", "utilities"))
    doc.add_budget(BudgetEnvelope("budget-transport", "Transport", 260.00, 0.0, "expense", "expense-household", "transport"))
    doc.add_budget(BudgetEnvelope("budget-eating-out", "Eating Out", 180.00, 0.0, "expense", "expense-household", "eating-out"))
    doc.add_budget(BudgetEnvelope("budget-salary", "Salary", 4500.00, 0.0, "income", "income-main", "salary"))

    doc.add_transaction(Transaction("txn-grocery-1", "everyday", "2026-06-04", "expense", "expense-household", "groceries", "Groceries", 126.40))
    doc.add_transaction(Transaction("txn-utility-1", "everyday", "2026-06-07", "expense", "expense-household", "utilities", "Power bill", 190.00))
    doc.add_transaction(Transaction("txn-salary-1", "everyday", "2026-06-01", "income", "income-main", "salary", "Salary", 2250.00))
    ensure_default_import_rules(doc)
    doc.regenerate_periods()
    return doc
}

return {
    Account = Account,
    Envelope = Envelope,
    EnvelopeFolder = EnvelopeFolder,
    ImportRule = ImportRule,
    TransactionSplit = TransactionSplit,
    Transaction = Transaction,
    BudgetEnvelope = BudgetEnvelope,
    DoughDocument = DoughDocument,
    account_from_table = account_from_table,
    envelope_from_table = envelope_from_table,
    folder_from_table = folder_from_table,
    import_rule_from_table = import_rule_from_table,
    split_from_table = split_from_table,
    transaction_from_table = transaction_from_table,
    budget_from_table = budget_from_table,
    ensure_default_import_rules = ensure_default_import_rules,
    document_from_table = document_from_table,
    sample_document = sample_document
}
