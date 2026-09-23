#!/usr/bin/env bash
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL2DOMAIN="${SCRIPT_DIR}/sql2domain"

# Default values
CONFIG_FILE="parameters.json"
SQL_FILE=""
OUT_DIR=""
CONTEXT=""
MIGRATION_NAME=""
PROJECT=""
STARTUP_PROJECT=""
MIGRATIONS_DIR=""
MOCK_MIGRATION=""

# Read defaults from parameters.json if it exists
if [ -f "$CONFIG_FILE" ]; then
    if command -v node >/dev/null 2>&1; then
        DEFAULT_SQL=$(node -e "try { console.log(require('./${CONFIG_FILE}').sql || '') } catch(e){}")
        DEFAULT_OUTDIR=$(node -e "try { console.log(require('./${CONFIG_FILE}').outdir || require('./${CONFIG_FILE}').projectDir || '') } catch(e){}")
        DEFAULT_CONTEXT=$(node -e "try { console.log(require('./${CONFIG_FILE}').context || '') } catch(e){}")
        SQL_FILE="${DEFAULT_SQL}"
        OUT_DIR="${DEFAULT_OUTDIR}"
        CONTEXT="${DEFAULT_CONTEXT}"
    fi
fi

# Fallback defaults if not set in config
if [ -z "$SQL_FILE" ] || [ ! -f "$SQL_FILE" ]; then
    CANDIDATE=$(find . -maxdepth 1 -name "*.sql" 2>/dev/null | head -n 1)
    if [ -n "$CANDIDATE" ]; then
        SQL_FILE="${CANDIDATE#./}"
    fi
fi
OUT_DIR="${OUT_DIR:-output}"
CONTEXT="${CONTEXT:-AppDbContext}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [SQL_FILE] [MIGRATION_NAME]

Automated 3-step EF Core migration workflow wrapper around sql2domain:
  1. Generate C# domain models, repositories, and DbContext without --migration
  2. Create native EF Core migration using 'dotnet ef migrations add'
  3. Inject isolated INSERT statements into the migration file using --migration

Options:
  -s, --sql <path>              Path to SQL file (default: ${SQL_FILE})
  -m, --name <name>             Migration name (default: Add<TableName> derived from SQL)
  -o, --outdir <path>           Output directory for C# files (default: ${OUT_DIR})
  -c, --context <name>          DbContext class name (default: ${CONTEXT})
  -p, --project <path>          Path to .csproj file or directory for dotnet ef
  --startup-project <path>      Path to startup project for dotnet ef
  --migrations-dir <path>       Directory to search for generated migrations
  --mock-migration <path>       Use existing migration file (skips 'dotnet ef' call for testing)
  -h, --help                    Show this help message and exit

Examples:
  $(basename "$0")
  $(basename "$0") schema.sql AddUser
  $(basename "$0") --sql schema.sql --name AddUser --context AppDbContext --project ./src/MyProject
EOF
    exit 0
}

# Parse options
POSITIONAL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--sql)
            SQL_FILE="$2"; shift 2 ;;
        -m|--name)
            MIGRATION_NAME="$2"; shift 2 ;;
        -o|--outdir)
            OUT_DIR="$2"; shift 2 ;;
        -c|--context)
            CONTEXT="$2"; shift 2 ;;
        -p|--project)
            PROJECT="$2"; shift 2 ;;
        --startup-project)
            STARTUP_PROJECT="$2"; shift 2 ;;
        --migrations-dir)
            MIGRATIONS_DIR="$2"; shift 2 ;;
        --mock-migration)
            MOCK_MIGRATION="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        -*)
            echo "Unknown option: $1" >&2
            usage ;;
        *)
            POSITIONAL_ARGS+=("$1"); shift ;;
    esac
done

# Positional arguments fallback
if [ ${#POSITIONAL_ARGS[@]} -ge 1 ]; then
    SQL_FILE="${POSITIONAL_ARGS[0]}"
fi
if [ ${#POSITIONAL_ARGS[@]} -ge 2 ]; then
    MIGRATION_NAME="${POSITIONAL_ARGS[1]}"
fi

if [ ! -f "$SQL_FILE" ]; then
    echo "Error: SQL file not found at '$SQL_FILE'." >&2
    exit 1
fi

if [ ! -f "$SQL2DOMAIN" ]; then
    echo "Error: sql2domain script not found at '$SQL2DOMAIN'." >&2
    exit 1
fi

# Auto-detect table name from SQL file if migration name not provided
if [ -z "$MIGRATION_NAME" ]; then
    TABLE_NAME=$(node -e "
        const fs = require('fs');
        try {
            const sql = fs.readFileSync(process.argv[1], 'utf8');
            const m = sql.match(/CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?(?:\[?[\w]+\]?\.)?\[?([\w]+)\]?/i);
            if (m) console.log(m[1]);
        } catch(e) {}
    " "$SQL_FILE" 2>/dev/null || true)
    if [ -n "$TABLE_NAME" ]; then
        MIGRATION_NAME="Add${TABLE_NAME}"
    else
        MIGRATION_NAME="AddInitialTableData"
    fi
fi

echo "============================================================"
echo "  sql2domain Migration Generator Workflow"
echo "  SQL File:       $SQL_FILE"
echo "  Migration Name: $MIGRATION_NAME"
echo "  Output Dir:     $OUT_DIR"
echo "  DbContext:      $CONTEXT"
echo "============================================================"
echo ""

export PATH="${PATH}:${HOME}/.dotnet/tools"

# Ensure dotnet-ef tool is available
if ! command -v dotnet-ef >/dev/null 2>&1 && ! dotnet ef --version >/dev/null 2>&1; then
    echo "dotnet-ef tool not found. Installing dotnet-ef globally..."
    dotnet tool install --global dotnet-ef || true
    export PATH="${PATH}:${HOME}/.dotnet/tools"
fi

# -----------------------------------------------------------------------------
# Step 1: Generate the Models (without --migration)
# -----------------------------------------------------------------------------
echo -e "\x1b[34m[1/3] Generating Models, Repositories, and DbContext partial...\x1b[0m"
node "$SQL2DOMAIN" --no-migration --sql "$SQL_FILE" --outdir "$OUT_DIR" --context "$CONTEXT"
echo -e "\x1b[32m✓ Step 1 complete: C# models and DbContext updated.\x1b[0m\n"

TARGET_PROJECT="${PROJECT:-$OUT_DIR}"

# Ensure project dependencies are restored before invoking dotnet ef
echo -e "\x1b[34mRestoring project dependencies for ${TARGET_PROJECT}...\x1b[0m"
dotnet restore "$TARGET_PROJECT"
echo -e "\x1b[32m✓ Project dependencies restored.\x1b[0m\n"

# -----------------------------------------------------------------------------
# Step 2: Create the Migration with EF Core
# -----------------------------------------------------------------------------
echo -e "\x1b[34m[2/3] Generating EF Core migration: ${MIGRATION_NAME}...\x1b[0m"
MIGRATION_FILE=""

if [ -n "$MOCK_MIGRATION" ]; then
    echo "Using existing migration file: $MOCK_MIGRATION"
    MIGRATION_FILE="$MOCK_MIGRATION"
else
    EF_ARGS=("migrations" "add" "$MIGRATION_NAME" "--context" "$CONTEXT" "--project" "$TARGET_PROJECT")
    if [ -n "$STARTUP_PROJECT" ]; then
        EF_ARGS+=("--startup-project" "$STARTUP_PROJECT")
    fi

    if [ -n "$MIGRATIONS_DIR" ]; then
        EF_ARGS+=("--output-dir" "$MIGRATIONS_DIR")
        SEARCH_DIR="$MIGRATIONS_DIR"
        if [ ! -d "$SEARCH_DIR" ] && [ -d "${TARGET_PROJECT}/${MIGRATIONS_DIR}" ]; then
            SEARCH_DIR="${TARGET_PROJECT}/${MIGRATIONS_DIR}"
        fi
    else
        EF_ARGS+=("--output-dir" "Migrations")
        SEARCH_DIR="${TARGET_PROJECT}/Migrations"
    fi

    echo "Running: dotnet ef ${EF_ARGS[*]}"
    dotnet ef "${EF_ARGS[@]}"

    # Locate the newly generated migration file
    MIGRATION_FILE=$(find "$SEARCH_DIR" -type f -name "*_${MIGRATION_NAME}.cs" ! -name "*.Designer.cs" 2>/dev/null | sort | tail -n 1)

    if [ -z "$MIGRATION_FILE" ] || [ ! -f "$MIGRATION_FILE" ]; then
        # Broader search fallback in target project
        MIGRATION_FILE=$(find "$TARGET_PROJECT" -type f -name "*_${MIGRATION_NAME}.cs" ! -name "*.Designer.cs" 2>/dev/null | sort | tail -n 1)
    fi

    if [ -z "$MIGRATION_FILE" ] || [ ! -f "$MIGRATION_FILE" ]; then
        echo -e "\x1b[31mError: Could not locate generated migration file for '${MIGRATION_NAME}'.\x1b[0m" >&2
        exit 1
    fi
fi

echo -e "\x1b[32m✓ Step 2 complete: Found migration file at ${MIGRATION_FILE}\x1b[0m\n"

# -----------------------------------------------------------------------------
# Step 3: Inject the Data (with --migration)
# -----------------------------------------------------------------------------
echo -e "\x1b[34m[3/3] Injecting INSERT statements into migration...\x1b[0m"
node "$SQL2DOMAIN" --sql "$SQL_FILE" --outdir "$OUT_DIR" --context "$CONTEXT" --migration "$MIGRATION_FILE"
echo -e "\x1b[32m✓ Step 3 complete: INSERT data injected into ${MIGRATION_FILE}.\x1b[0m\n"

echo -e "\x1b[32m\x1b[1mSuccessfully completed full migration generation workflow!\x1b[0m"
