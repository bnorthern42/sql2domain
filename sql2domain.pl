#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename qw(basename dirname);
use File::Path qw(make_path);
use File::Spec::Functions qw(catfile catdir);
use JSON::PP;

my $migration_path = '';
my $sql_path = '';
my $out_dir = '';
my $config_path = 'parameters.json';
my $no_migration = 0;
my $context_name = '';

my @args = @ARGV;
for (my $i = 0; $i < scalar @args; $i++) {
    my $arg = $args[$i];
    if ($arg eq '--migration' && $i + 1 < scalar @args) {
        $migration_path = $args[++$i];
    } elsif ($arg eq '--no-migration') {
        $no_migration = 1;
    } elsif ($arg eq '--sql' && $i + 1 < scalar @args) {
        $sql_path = $args[++$i];
    } elsif ($arg eq '--outdir' && $i + 1 < scalar @args) {
        $out_dir = $args[++$i];
    } elsif ($arg eq '--context' && $i + 1 < scalar @args) {
        $context_name = $args[++$i];
    } elsif ($arg eq '--config' && $i + 1 < scalar @args) {
        $config_path = $args[++$i];
    }
}

my $config = {
    encapsulateNamespace => JSON::PP::true,
    copyright => ''
};

if (-f $config_path) {
    eval {
        open my $fh, '<:encoding(UTF-8)', $config_path or die "Cannot open $config_path: $!";
        local $/;
        my $content = <$fh>;
        close $fh;
        my $parsed = decode_json($content);
        if (ref($parsed) eq 'HASH') {
            $config->{$_} = $parsed->{$_} for keys %$parsed;
        }
    };
    if ($@) {
        print STDERR "\e[33mWarning: Could not read or parse config file $config_path: $@\e[0m\n";
    }
}

$migration_path ||= $config->{migration} || '';
$sql_path ||= $config->{sql} || '';
$out_dir ||= $config->{outdir} || $config->{projectDir} || '';
$context_name ||= $config->{context} || 'AppDbContext';
if ($config->{noMigration}) {
    $no_migration = 1;
}

if (!$sql_path || !$out_dir || (!$migration_path && !$no_migration)) {
    print STDERR "Usage: sql2domain.pl [--config parameters.json] [--no-migration | --migration <path>] --sql <path> --outdir <path> [--context <name>]\n";
    exit 1;
}

my $sql_content = '';
my $table_name = '';
my $entity_name = '';
my $feature_name = '';
my @columns;

eval {
    open my $fh, '<:encoding(UTF-8)', $sql_path or die "Cannot open $sql_path: $!";
    local $/;
    $sql_content = <$fh>;
    close $fh;

    if ($sql_content =~ /CREATE\s+TABLE\s+\[?([\w]+)\]?/i) {
        $table_name = $1;
    } else {
        die "Could not find a CREATE TABLE statement in the provided SQL file.\n";
    }

    $entity_name = $table_name;
    if ($entity_name =~ /ies$/) {
        $entity_name =~ s/ies$/y/;
    } elsif ($entity_name =~ /s$/) {
        $entity_name =~ s/s$//;
    }

    $feature_name = $entity_name;
    my @common_suffixes = ('Specification', 'Type', 'Category', 'Detail', 'Setting', 'Config');
    for my $suffix (@common_suffixes) {
        if ($feature_name =~ /\Q$suffix\E$/ && $feature_name ne $suffix) {
            $feature_name =~ s/\Q$suffix\E$//;
            last;
        }
    }

    if ($sql_content =~ /CREATE\s+TABLE\s+\[?[\w]+\]?\s*\(([\s\S]*?)\)\s*;/i) {
        my $body = $1;
        my @body_lines = split /,/, $body;
        for my $line (@body_lines) {
            $line =~ s/^\s+|\s+$//g;
            next if $line eq '';
            if ($line =~ /^\[?([\w]+)\]?\s+([\w]+)(?:\(.*?\))?/i) {
                my $col_name = $1;
                my $sql_type = uc($2);

                my $cs_type = 'string';
                if ($sql_type =~ /^(INT|BIGINT|SMALLINT|TINYINT)$/) {
                    $cs_type = 'int';
                    $cs_type = 'long' if $sql_type eq 'BIGINT';
                    $cs_type = 'short' if $sql_type eq 'SMALLINT';
                    $cs_type = 'byte' if $sql_type eq 'TINYINT';
                } elsif ($sql_type eq 'BIT') {
                    $cs_type = 'bool';
                } elsif ($sql_type =~ /^(DECIMAL|NUMERIC|MONEY)$/) {
                    $cs_type = 'decimal';
                } elsif ($sql_type =~ /^(FLOAT|REAL)$/) {
                    $cs_type = 'double';
                } elsif ($sql_type =~ /^(DATE|DATETIME|DATETIME2|SMALLDATETIME)$/) {
                    $cs_type = 'DateTime';
                } elsif ($sql_type eq 'UNIQUEIDENTIFIER') {
                    $cs_type = 'Guid';
                }

                if (uc($col_name) ne 'PRIMARY' && uc($col_name) ne 'CONSTRAINT' && uc($col_name) ne 'FOREIGN') {
                    push @columns, { name => $col_name, type => $cs_type, sql_type => $sql_type };
                }
            }
        }
    }
};
if ($@) {
    print STDERR "Error reading SQL file: $@\n";
    exit 1;
}

if (!$no_migration && $migration_path) {
    eval {
        open my $fh, '<:encoding(UTF-8)', $migration_path or die "Cannot open $migration_path: $!";
        local $/;
        my $migration_content = <$fh>;
        close $fh;

        my $up_regex = qr/(protected\s+override\s+void\s+Up\s*\(\s*MigrationBuilder\s+migrationBuilder\s*\)\s*\{)/;
        my $down_regex = qr/(protected\s+override\s+void\s+Down\s*\(\s*MigrationBuilder\s+migrationBuilder\s*\)\s*\{)/;

        if ($migration_content =~ $up_regex && $migration_content =~ $down_regex) {
            my $safe_sql = $sql_content;
            $safe_sql =~ s/"/""/g;

            my $up_injection = "\n            migrationBuilder.Sql(\@\"$safe_sql\");";
            $migration_content =~ s/$up_regex/$1$up_injection/;

            my $down_injection = "\n            migrationBuilder.DropTable(\"$table_name\");";
            $migration_content =~ s/$down_regex/$1$down_injection/;

            open my $out_fh, '>:encoding(UTF-8)', $migration_path or die "Cannot write $migration_path: $!";
            print $out_fh $migration_content;
            close $out_fh;

            print "\e[32mSuccessfully modified migration:\e[0m $migration_path\n";
        } else {
            print STDERR "\e[31mCould not find Up or Down methods in the migration file.\e[0m\n";
        }
    };
    if ($@) {
        print STDERR "\e[31mError processing migration file:\e[0m $@\n";
        exit 1;
    }
}

sub ensure_dir {
    my ($dir) = @_;
    make_path($dir) unless -d $dir;
}

sub write_file_content {
    my ($file_path, $content) = @_;
    open my $fh, '>:encoding(UTF-8)', $file_path or die "Cannot write $file_path: $!";
    print $fh $content;
    close $fh;
}

my $namespace_base = basename($out_dir);
my $copyright_header = ($config->{copyright} && $config->{copyright} ne '') ? "$config->{copyright}\n\n" : '';

sub wrap_namespace {
    my ($namespace_name, $content) = @_;
    my $encapsulate = 1;
    if (exists $config->{encapsulateNamespace}) {
        if (JSON::PP::is_bool($config->{encapsulateNamespace})) {
            $encapsulate = $config->{encapsulateNamespace} ? 1 : 0;
        } elsif ($config->{encapsulateNamespace} eq 'false' || !$config->{encapsulateNamespace}) {
            $encapsulate = 0;
        }
    }

    if ($encapsulate) {
        my @lines = split /\n/, $content, -1;
        my $indented = join("\n", map { $_ ne '' ? "    $_" : "" } @lines);
        return "namespace $namespace_name\n{\n$indented\n}\n";
    } else {
        return "namespace $namespace_name;\n\n$content\n";
    }
}

# Generate C# properties from columns
my $properties_content = join("\n", map { "        public $_->{type} $_->{name} { get; set; }" } @columns);
my $clean_properties = $properties_content;
$clean_properties =~ s/^ {4}//gm;

# 1. Models
my $models_dir = catdir($out_dir, 'Models');
ensure_dir($models_dir);

my $entity_file = catfile($models_dir, "$entity_name.cs");
my $entity_content_inner = "public class $entity_name\n{\n$clean_properties\n}";
my $entity_content = "${copyright_header}" . wrap_namespace("$namespace_base.Models", $entity_content_inner);
write_file_content($entity_file, $entity_content);
print "\e[36mCreated:\e[0m $entity_file\n";

my $db_context_partial_file = catfile($models_dir, "$context_name.$entity_name.cs");
my $db_context_partial_content_inner = <<"EOF";
public partial class $context_name
{
    public DbSet<$entity_name> $table_name { get; set; }

    partial void OnModelCreating$entity_name(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<$entity_name>(entity =>
        {
            entity.ToTable("$table_name");
            // Add Fluent API configurations here if necessary
        });
    }
}
EOF
chomp $db_context_partial_content_inner;
my $db_context_partial_content = "${copyright_header}using Microsoft.EntityFrameworkCore;\n\n" . wrap_namespace("$namespace_base.Models", $db_context_partial_content_inner);
write_file_content($db_context_partial_file, $db_context_partial_content);
print "\e[36mCreated:\e[0m $db_context_partial_file\n";

# 2. Mappings
my $mappings_dir = catdir($out_dir, 'Mappings');
ensure_dir($mappings_dir);

my $mapping_profile_file = catfile($mappings_dir, "${entity_name}Profile.cs");
my $mapping_profile_content_inner = <<"EOF";
public class ${entity_name}Profile : Profile
{
    public ${entity_name}Profile()
    {
        CreateMap<$entity_name, ${entity_name}StandardData>();
    }
}
EOF
chomp $mapping_profile_content_inner;
my $mapping_profile_content = "${copyright_header}using AutoMapper;\nusing $namespace_base.Models;\nusing $namespace_base.StandardData;\n\n" . wrap_namespace("$namespace_base.Mappings", $mapping_profile_content_inner);
write_file_content($mapping_profile_file, $mapping_profile_content);
print "\e[36mCreated:\e[0m $mapping_profile_file\n";

# 3. Domain
my $domain_dir = catdir($out_dir, 'Domain', $feature_name);
ensure_dir($domain_dir);

my $result_file = catfile($domain_dir, "${feature_name}Result.cs");
my $result_content_inner = <<"EOF";
public record ${feature_name}Result
{
    // Add domain result properties here
}
EOF
chomp $result_content_inner;
my $result_content = "${copyright_header}" . wrap_namespace("$namespace_base.Domain.$feature_name", $result_content_inner);
write_file_content($result_file, $result_content);
print "\e[36mCreated:\e[0m $result_file\n";

my $logic_service_file = catfile($domain_dir, "${feature_name}LogicService.cs");
my $logic_service_content_inner = <<"EOF";
public class ${feature_name}LogicService
{
    private readonly IStandardDataRepository<I${entity_name}StandardData> _repository;

    public ${feature_name}LogicService(IStandardDataRepository<I${entity_name}StandardData> repository)
    {
        _repository = repository;
    }

    public ${feature_name}Result Execute()
    {
        // Business logic
        return new ${feature_name}Result();
    }
}
EOF
chomp $logic_service_content_inner;
my $logic_service_content = "${copyright_header}using System.Collections.Generic;\nusing $namespace_base.Repositories.Databases;\nusing $namespace_base.StandardData;\n\n" . wrap_namespace("$namespace_base.Domain.$feature_name", $logic_service_content_inner);
write_file_content($logic_service_file, $logic_service_content);
print "\e[36mCreated:\e[0m $logic_service_file\n";

# 4. StandardData
my $standard_data_dir = catdir($out_dir, 'StandardData');
ensure_dir($standard_data_dir);

my $interface_props = join("\n", map { "        $_->{type} $_->{name} { get; }" } @columns);
my $clean_interface_props = $interface_props;
$clean_interface_props =~ s/^ {4}//gm;

my $interface_file = catfile($standard_data_dir, "I${entity_name}StandardData.cs");
my $interface_content_inner = "public interface I${entity_name}StandardData\n{\n$clean_interface_props\n}";
my $interface_content = "${copyright_header}" . wrap_namespace("$namespace_base.StandardData", $interface_content_inner);
write_file_content($interface_file, $interface_content);
print "\e[36mCreated:\e[0m $interface_file\n";

my $standard_data_props = join("\n", map { "        public $_->{type} $_->{name} { get; private set; }" } @columns);
my $clean_standard_data_props = $standard_data_props;
$clean_standard_data_props =~ s/^ {4}//gm;

my $standard_data_file = catfile($standard_data_dir, "${entity_name}StandardData.cs");
my $standard_data_content_inner = "public class ${entity_name}StandardData : I${entity_name}StandardData\n{\n    private ${entity_name}StandardData()\n    {\n    }\n\n$clean_standard_data_props\n}";
my $standard_data_content = "${copyright_header}" . wrap_namespace("$namespace_base.StandardData", $standard_data_content_inner);
write_file_content($standard_data_file, $standard_data_content);
print "\e[36mCreated:\e[0m $standard_data_file\n";

# 5. Repositories
my $repositories_dir = catdir($out_dir, 'Repositories', 'Databases');
ensure_dir($repositories_dir);

my $repository_file = catfile($repositories_dir, "${entity_name}StandardDataRepository.cs");
my $repository_content_inner = <<"EOF";
public interface IStandardDataRepository<T> : IReadOnlyCollection<T>
{
}

public class ${entity_name}StandardDataRepository : IStandardDataRepository<I${entity_name}StandardData>
{
    private readonly $context_name _context;
    private readonly IMapper _mapper;

    public ${entity_name}StandardDataRepository($context_name context, IMapper mapper)
    {
        _context = context;
        _mapper = mapper;
    }

    public IEnumerator<I${entity_name}StandardData> GetEnumerator()
    {
        var data = _context.$table_name.ToList();
        var standardData = _mapper.Map<List<${entity_name}StandardData>>(data);
        return standardData.Cast<I${entity_name}StandardData>().GetEnumerator();
    }

    System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator() => GetEnumerator();

    public int Count => _context.$table_name.Count();
}
EOF
chomp $repository_content_inner;
my $repository_content = "${copyright_header}using System.Collections.Generic;\nusing System.Linq;\nusing AutoMapper;\nusing $namespace_base.Models;\nusing $namespace_base.StandardData;\n\n" . wrap_namespace("$namespace_base.Repositories.Databases", $repository_content_inner);
write_file_content($repository_file, $repository_content);
print "\e[36mCreated:\e[0m $repository_file\n";

print "\n\e[32m\e[1mScaffolding completed successfully!\e[0m\n\n";
