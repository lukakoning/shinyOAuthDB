# Native Flight SQL transport check

This fixture runs the actual Apache Arrow ADBC Flight SQL driver and adbi
against a local TLS Flight SQL server. It checks bearer authentication on
RPCs, separate visitors, token replacement, prepared parameter binding,
Arrow result cleanup, permission errors and certificate verification.

It is a protocol fixture, not a Dremio deployment. It uses synthetic,
allowlisted bearer strings and does not implement JWT issuer validation,
Dremio user mappings or Dremio authorization policy.

From the repository root, create a Python 3.11 or later environment and install the
fixture dependencies:

```sh
python -m venv .validation/dremio/venv
# Windows:
.validation/dremio/venv/Scripts/python.exe -m pip install -r integration/dremio-flightsql/requirements.txt
# Linux/macOS:
.validation/dremio/venv/bin/python -m pip install -r integration/dremio-flightsql/requirements.txt
```

Install the package's R test dependencies, including adbi and
adbcdrivermanager 0.25.0 or later. Run:

```sh
Rscript --vanilla tools/check-dremio.R .validation/dremio/venv/Scripts/python.exe
```

Use the `bin/python` path on Linux/macOS. Extra positional arguments add R
library paths. The Python wheel supplies the native driver path to the R
runner; it is not installed into the user's driver registry. The server
listens only on localhost, creates a temporary test certificate and stops
when the runner exits.

Live Dremio acceptance additionally needs a configured Enterprise token
provider and users with different database permissions. Verify the
database principal, table and row restrictions, token expiry, long-running
queries, prepared statements and result types. Cloud authentication is a
separate acceptance target. See the [backend decision](../../docs/dremio-backend.md).
