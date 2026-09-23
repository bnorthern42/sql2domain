# sql2domain

A toolkit to scaffold C# Domain-Driven Design (DDD) structures and manage Entity Framework Core migrations from raw SQL table definitions.

## Overview

The toolkit consists of two primary components:
1. `sql2domain` / `sql2domain.pl`: Scaffolding tool available in both Node.js (`sql2domain`) and Perl (`sql2domain.pl`) implementations with identical CLI options and output. Parses SQL `CREATE TABLE` statements to generate C# domain models, DbContext partials, AutoMapper profiles, domain services, standard data interfaces, and database repositories. It also optionally injects SQL into an existing EF Core migration file.
2. `generate_migration.sh`: Shell script that automates the end-to-end 3-step EF Core migration lifecycle.

## Requirements

- Node.js (v14+ recommended, if using `sql2domain`)
- Perl 5.14+ (core `JSON::PP` module, if using `sql2domain.pl`)
- .NET SDK (v6.0+ recommended)
- `dotnet-ef` CLI tool (automatically installed if missing when running `generate_migration.sh`)

## sql2domain / sql2domain.pl

### Usage

```bash
# Node.js
./sql2domain [--config parameters.json] [--no-migration | --migration <path>] --sql <path> --outdir <path> [--context <name>]

# Perl
./sql2domain.pl [--config parameters.json] [--no-migration | --migration <path>] --sql <path> --outdir <path> [--context <name>]
```

### Options

- `--sql <path>`: Path to the SQL file containing the `CREATE TABLE` and optional `INSERT` statements.
- `--outdir <path>`: Target directory for generated C# files.
- `--migration <path>`: Path to an EF Core migration file to inject `migrationBuilder.Sql(...)` and `DropTable` statements into.
- `--no-migration`: Skips migration file injection (scaffolds C# models and repositories only).
- `--context <name>`: Name of the DbContext class (default: `AppDbContext`).
- `--config <path>`: Path to a JSON configuration file (default: `parameters.json`).

### Generated Artifacts

Given a table definition, `sql2domain` creates:
- `Models/<Entity>.cs`: Plain C# entity with matching properties.
- `Models/<DbContext>.<Entity>.cs`: Partial DbContext class with `DbSet<T>` and `OnModelCreating` configuration.
- `Mappings/<Entity>Profile.cs`: AutoMapper profile mapping the entity to its standard data representation.
- `Domain/<Feature>/<Feature>Result.cs`: Domain result record.
- `Domain/<Feature>/<Feature>LogicService.cs`: Domain logic service consuming the standard data repository.
- `StandardData/I<Entity>StandardData.cs`: Read-only interface for data abstraction.
- `StandardData/<Entity>StandardData.cs`: Immutable standard data class implementing the interface.
- `Repositories/Databases/<Entity>StandardDataRepository.cs`: Generic repository implementation over the DbContext.

---

## generate_migration.sh

Automates the complete EF Core migration workflow in three steps:
1. Generates C# models, repositories, and DbContext partial without modifying migrations (`sql2domain --no-migration`).
2. Creates the EF Core migration via `dotnet ef migrations add`.
3. Injects the SQL data statements into the newly generated migration file (`sql2domain --migration`).

### Usage

```bash
./generate_migration.sh [OPTIONS] [SQL_FILE] [MIGRATION_NAME]
```

### Options

- `-s, --sql <path>`: Path to the SQL file.
- `-m, --name <name>`: Migration name (default: `Add<TableName>` derived from SQL).
- `-o, --outdir <path>`: Output directory for C# domain files (default: `output`).
- `-c, --context <name>`: DbContext class name (default: `AppDbContext`).
- `-p, --project <path>`: Path to the target `.csproj` or directory for `dotnet ef`.
- `--startup-project <path>`: Path to the startup project for `dotnet ef`.
- `--migrations-dir <path>`: Subdirectory for migrations (default: `Migrations`).
- `--mock-migration <path>`: Path to an existing migration file (skips `dotnet ef` execution, useful for testing).
- `-h, --help`: Displays the help message.

---

## Examples Directory (`examples/`)

A ready-to-run example is provided in the `examples/` directory:
- `examples/dogs.sql`: Sample SQL schema and seed data for a `Dogs` table.
- `examples/parameters.json`: Example configuration file.
- `examples/output/`: Pre-generated C# domain structure created by `sql2domain`.

### 1. Input SQL (`examples/dogs.sql`)

```sql
CREATE TABLE [Dogs] (
    [Id] INT NOT NULL,
    [Name] VARCHAR(50) NOT NULL,
    [Breed] VARCHAR(50) NOT NULL,
    [Weight] DECIMAL(5,2) NOT NULL,
    [Age] INT NOT NULL,
    [IsVaccinated] BIT NOT NULL
);

INSERT INTO [Dogs] ([Id], [Name], [Breed], [Weight], [Age], [IsVaccinated])
VALUES
    (1, 'Max', 'Golden Retriever', 30.50, 4, 1),
    (2, 'Bella', 'French Bulldog', 11.20, 2, 1),
    (3, 'Charlie', 'German Shepherd', 34.00, 5, 0);
```

### 2. Execution

Run standalone domain scaffolding:
```bash
./sql2domain --no-migration --sql examples/dogs.sql --outdir examples/output --context AppDbContext
```

Or run using the configuration file:
```bash
./sql2domain --no-migration --config examples/parameters.json
```

Or run the complete migration workflow:
```bash
./generate_migration.sh examples/dogs.sql AddDogs --context AppDbContext --project ./src/MyProject
```

### 3. Generated Code Samples

Entity Model (`examples/output/Models/Dog.cs`):
```csharp
namespace output.Models
{
    public class Dog
    {
        public int Id { get; set; }
        public string Name { get; set; }
        public string Breed { get; set; }
        public decimal Weight { get; set; }
        public int Age { get; set; }
        public bool IsVaccinated { get; set; }
    }
}
```

DbContext Partial (`examples/output/Models/AppDbContext.Dog.cs`):
```csharp
namespace output.Models
{
    public partial class AppDbContext
    {
        public DbSet<Dog> Dogs { get; set; }

        partial void OnModelCreatingDog(ModelBuilder modelBuilder)
        {
            modelBuilder.Entity<Dog>(entity =>
            {
                entity.ToTable("Dogs");
            });
        }
    }
}
```

Standard Data Interface (`examples/output/StandardData/IDogStandardData.cs`):
```csharp
namespace output.StandardData
{
    public interface IDogStandardData
    {
        int Id { get; }
        string Name { get; }
        string Breed { get; }
        decimal Weight { get; }
        int Age { get; }
        bool IsVaccinated { get; }
    }
}
```

Standard Data Repository (`examples/output/Repositories/Databases/DogStandardDataRepository.cs`):
```csharp
namespace output.Repositories.Databases
{
    public class DogStandardDataRepository : IStandardDataRepository<IDogStandardData>
    {
        private readonly AppDbContext _context;
        private readonly IMapper _mapper;

        public DogStandardDataRepository(AppDbContext context, IMapper mapper)
        {
            _context = context;
            _mapper = mapper;
        }

        public IEnumerator<IDogStandardData> GetEnumerator()
        {
            var data = _context.Dogs.ToList();
            var standardData = _mapper.Map<List<DogStandardData>>(data);
            return standardData.Cast<IDogStandardData>().GetEnumerator();
        }

        public int Count => _context.Dogs.Count();
    }
}
```

Injected EF Core Migration (`Migrations/xxxx_AddDogs.cs`):
```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    migrationBuilder.Sql(@"CREATE TABLE [Dogs] (
    [Id] INT NOT NULL,
    [Name] VARCHAR(50) NOT NULL,
    [Breed] VARCHAR(50) NOT NULL,
    [Weight] DECIMAL(5,2) NOT NULL,
    [Age] INT NOT NULL,
    [IsVaccinated] BIT NOT NULL
);
INSERT INTO [Dogs] ([Id], [Name], [Breed], [Weight], [Age], [IsVaccinated])
VALUES
    (1, 'Max', 'Golden Retriever', 30.50, 4, 1),
    (2, 'Bella', 'French Bulldog', 11.20, 2, 1),
    (3, 'Charlie', 'German Shepherd', 34.00, 5, 0);");
}

protected override void Down(MigrationBuilder migrationBuilder)
{
    migrationBuilder.DropTable("Dogs");
}
```

---

## Configuration File (parameters.json)

Both tools can optionally read defaults from a `parameters.json` file in the working directory:

```json
{
  "sql": "dogs.sql",
  "outdir": "./output",
  "context": "AppDbContext",
  "encapsulateNamespace": true,
  "copyright": "// Copyright (c) Example. All rights reserved."
}
```
