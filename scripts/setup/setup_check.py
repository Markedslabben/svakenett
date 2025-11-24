#!/usr/bin/env python3
"""
Setup verification script - checks all prerequisites for svakenett project

Verifies:
1. Docker is running
2. PostgreSQL+PostGIS container is healthy
3. Database connection works
4. PostGIS extension is available
5. Python dependencies are installed
"""

import subprocess
import sys
from pathlib import Path

# Color codes for terminal output
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
RESET = "\033[0m"


def print_status(message: str, success: bool):
    """Print colored status message"""
    symbol = f"{GREEN}✓{RESET}" if success else f"{RED}✗{RESET}"
    print(f"{symbol} {message}")


def check_docker():
    """Check if Docker is running"""
    try:
        result = subprocess.run(
            ["docker", "ps"],
            capture_output=True,
            text=True,
            timeout=5
        )
        success = result.returncode == 0
        print_status("Docker is running", success)
        return success
    except Exception as e:
        print_status(f"Docker check failed: {e}", False)
        return False


def check_postgis_container():
    """Check if svakenett-postgis container is running"""
    try:
        result = subprocess.run(
            ["docker", "ps", "--filter", "name=svakenett-postgis", "--format", "{{.Status}}"],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0 and result.stdout.strip():
            status = result.stdout.strip()
            is_healthy = "healthy" in status.lower() or "up" in status.lower()
            print_status(f"PostgreSQL container: {status}", is_healthy)
            return is_healthy
        else:
            print_status("PostgreSQL container not found", False)
            print(f"  {YELLOW}Run: docker-compose up -d{RESET}")
            return False

    except Exception as e:
        print_status(f"Container check failed: {e}", False)
        return False


def check_database_connection():
    """Check database connection via psql"""
    try:
        result = subprocess.run(
            [
                "docker", "exec", "svakenett-postgis",
                "psql", "-U", "postgres", "-d", "svakenett",
                "-c", "SELECT version();"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        success = result.returncode == 0
        if success:
            # Extract version from output
            version_line = result.stdout.split('\n')[2] if result.stdout else "Unknown"
            print_status(f"PostgreSQL connection works", True)
            print(f"  Version: {version_line.strip()[:60]}...")
        else:
            print_status("PostgreSQL connection failed", False)
            print(f"  Error: {result.stderr}")

        return success

    except Exception as e:
        print_status(f"Database connection check failed: {e}", False)
        return False


def check_postgis_extension():
    """Check if PostGIS extension is available"""
    try:
        result = subprocess.run(
            [
                "docker", "exec", "svakenett-postgis",
                "psql", "-U", "postgres", "-d", "svakenett",
                "-c", "SELECT PostGIS_Version();"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        success = result.returncode == 0
        if success:
            version_line = result.stdout.split('\n')[2] if result.stdout else "Unknown"
            print_status(f"PostGIS extension available", True)
            print(f"  Version: {version_line.strip()}")
        else:
            print_status("PostGIS extension not found", False)

        return success

    except Exception as e:
        print_status(f"PostGIS check failed: {e}", False)
        return False


def check_python_deps():
    """Check if critical Python dependencies are installed"""
    critical_deps = [
        "geopandas",
        "pandas",
        "sqlalchemy",
        "psycopg2",
        "shapely",
        "loguru"
    ]

    all_installed = True

    for dep in critical_deps:
        try:
            __import__(dep)
            print_status(f"Python: {dep} installed", True)
        except ImportError:
            print_status(f"Python: {dep} NOT installed", False)
            all_installed = False

    if not all_installed:
        print(f"\n  {YELLOW}Run: poetry install{RESET}")

    return all_installed


def check_database_schema():
    """Check if database tables exist"""
    try:
        result = subprocess.run(
            [
                "docker", "exec", "svakenett-postgis",
                "psql", "-U", "postgres", "-d", "svakenett",
                "-c", "SELECT tablename FROM pg_tables WHERE schemaname='public';"
            ],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            tables = [line.strip() for line in result.stdout.split('\n')[2:-3] if line.strip()]
            expected_tables = ['cabins', 'grid_companies', 'postal_codes', 'municipalities']

            if any(t in tables for t in expected_tables):
                print_status(f"Database schema initialized ({len(tables)} tables)", True)
                print(f"  Tables: {', '.join(tables[:5])}")
                return True
            else:
                print_status("Database schema not initialized", False)
                print(f"  {YELLOW}Schema will be created automatically when container starts{RESET}")
                return False
        else:
            print_status("Could not check database schema", False)
            return False

    except Exception as e:
        print_status(f"Schema check failed: {e}", False)
        return False


def main():
    print("=" * 60)
    print("Svakenett MVP - Setup Verification")
    print("=" * 60)
    print()

    checks = [
        ("Docker", check_docker),
        ("PostgreSQL Container", check_postgis_container),
        ("Database Connection", check_database_connection),
        ("PostGIS Extension", check_postgis_extension),
        ("Python Dependencies", check_python_deps),
        ("Database Schema", check_database_schema),
    ]

    results = []
    for name, check_func in checks:
        print(f"\n{name}:")
        print("-" * 60)
        result = check_func()
        results.append(result)

    print("\n" + "=" * 60)
    passed = sum(results)
    total = len(results)

    if passed == total:
        print(f"{GREEN}✓ All checks passed ({passed}/{total}){RESET}")
        print("\nYou're ready to start development!")
        print(f"\nNext step: poetry run python scripts/01_download_n50_data.py --region agder")
        return 0
    else:
        print(f"{YELLOW}⚠ Some checks failed ({passed}/{total}){RESET}")
        print("\nPlease resolve the issues above before proceeding.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
