# Shared reference: MDEV/MENT default assignees

Default assignee per subsystem for MDEV and MENT bug reports, used by the `jira-ticket` skill to suggest an assignee in the approval overview. Map the bug's primary component/subsystem to the name and surface it for signoff. Display names are in the table; their Jira usernames are pre-resolved below. Set with `--assignee <username>`. Resolve any new name via `/rest/api/2/user/search?username=<prefix>` (the param is `username`, NOT `query`).

Jira usernames: Sanja/Oleksandr Byelkin=`sanja`, Aleksey Midenkov=`midenok`, Monty Widenius=`monty`, Rucha Deodhar=`rucha174`, Sergei Golubchik=`serg`, Vladislav Vaintroub=`wlad`, Brandon Nesterenko=`bnestere`, Raghunandan Bhat=`raghunandan.bhat`, Thiru Balathandayuthapani=`thiru`, Seppo Jaakola=`seppo`, Georg Richter=`georg`, Sergei Petrunia=`psergei`, Daniel Black=`danblack`, Alexey Botchkov=`holyfoot`, Alexander Barkov=`bar`, Dmitry Shulga=`shulga`, Kristian Nielsen=`knielsen`, Yuchen Pei=`ycp`.

| Subsystem | Default assignee |
|---|---|
| Aggregate stored functions | Sanja Byelkin |
| Application periods | Aleksey Midenkov |
| Aria storage engine | Monty Widenius |
| Audit plugin | Rucha Deodhar |
| Authentication & Privilege | Sergei Golubchik |
| AWS key management | Vladislav Vaintroub |
| Backup locks | Monty Widenius |
| Binary logging (generic and XA) | Brandon Nesterenko |
| Character sets, collations | Raghunandan Bhat |
| Client programs | Sanja Byelkin |
| Compressed columns | Sanja Byelkin |
| Connect storage engine | Unassigned, or Sanja Byelkin (runtime) |
| Data types | Raghunandan Bhat |
| Diagnostics area | Rucha Deodhar |
| DDL (generic) | Sanja Byelkin |
| DML (generic) | Sanja Byelkin |
| Documentation | Do NOT create in MDEV -> Atlassian JIRA DOCS project |
| Dynamic columns | Sanja Byelkin |
| Encryption in Aria | Monty Widenius |
| Encryption in binlog | Brandon Nesterenko |
| Encryption in InnoDB | Thiru Balathandayuthapani |
| Events | Sanja Byelkin |
| Feedback plugin | (none) |
| Full-text search in InnoDB | Thiru Balathandayuthapani |
| Full-text search non-InnoDB | Sanja Byelkin |
| Galera | Seppo Jaakola |
| GIS | Rucha Deodhar / Sanja Byelkin |
| Handler (generic) | Sanja Byelkin |
| Innochecksum | Thiru Balathandayuthapani |
| InnoDB storage engine | Thiru Balathandayuthapani |
| Invisible columns | Aleksey Midenkov |
| JSON functions | Rucha Deodhar |
| Libmariadb | Georg Richter |
| Locking (generic) | Aleksey Midenkov |
| MariaBackup | Thiru Balathandayuthapani |
| Memroot | Raghunandan Bhat |
| Optimizer (generic) | Sergei Petrunia |
| Optimizer CTE | Sergei Petrunia |
| Packaging bintar | Sergei Golubchik |
| Packaging DEB | Daniel Black |
| Packaging RPM | Sergei Golubchik |
| Packaging Windows | Vladislav Vaintroub |
| PAM plugin | Sergei Golubchik |
| Parser | Raghunandan Bhat |
| Partitioning (generic) | Alexey Botchkov |
| Performance schema | Sergei Golubchik |
| PL/SQL | Alexander Barkov |
| Plugins (generic / not listed) | Sanja Byelkin |
| Plugin - Hashicorp Key Management | Rucha Deodhar |
| Prepared statements | Dmitry Shulga |
| Protocol (generic) | Vladislav Vaintroub |
| Query cache | Sanja Byelkin |
| Replication | Brandon Nesterenko |
| Replication - new binary log | Kristian Nielsen |
| RocksDB storage engine | Sergei Petrunia |
| Sequences | Sanja Byelkin |
| Smart_engine | Sergei Golubchik |
| Spider storage engine | Yuchen Pei |
| SSL | Sergei Golubchik |
| Storage engines (generic / not listed) | Sanja Byelkin |
| Storage Engine - S3 | Monty Widenius |
| Stored functions/procedures (generic) | Dmitry Shulga |
| System-versioned tables | Aleksey Midenkov |
| Systemd | (none) |
| Temporary tables (generic) | Sanja Byelkin |
| Thread pool | Vladislav Vaintroub |
| Time zones, temporal types | Raghunandan Bhat |
| Triggers (generic) | Dmitry Shulga |
| Unique blob indexes | Aleksey Midenkov |
| Vector search | Sergei Golubchik |
| Videx | Sergei Golubchik |
| Views | Sanja Byelkin |
| Virtual columns | Aleksey Midenkov |
| Window functions | Sergei Petrunia |
| WSREP | Seppo Jaakola |

Replication / binlog: generic replication AND binary logging (incl. binlog group-commit, the checkpoint machinery `do_checkpoint_request`/`ha_commit_checkpoint_request`, `RESET MASTER`, XA) default to Brandon Nesterenko (`bnestere`). The `Replication - new binary log` -> Kristian Nielsen (`knielsen`) row is ONLY the 13.0+ new binary-log implementation rewrite (fsp_binlog / archive log); a group-commit / checkpoint / RESET MASTER bug (e.g. MDEV-40038) is `bnestere`'s, not `knielsen`'s.

When a bug spans multiple subsystems, assign by the subsystem owning the ROOT cause (the feature fundamentally involved), NOT the surface symptom. A virtual-column read-set bug that asserts during the optimizer's filesort/range path is still a Virtual columns bug -> Aleksey Midenkov (`midenok`), even though it surfaces via the Optimizer (e.g. MDEV-40024). A sibling's assignee is only a hint, and only when it is TRULY the same bug - do not over-correct the map from a loosely-related sibling. Resolve display name -> Jira username via `/rest/api/2/user/search?username=<prefix>` (the param is `username`, NOT `query`). Surface it in the approval overview as `Assignee: Display Name / username`; on the user's approval, file WITH `--assignee <username>` so the filed ticket matches the signoff. The signoff includes the assignee - do NOT file unassigned when an assignee was shown and approved.
