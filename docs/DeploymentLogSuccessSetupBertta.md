# Sample run of deploymment script

```sh

● Bash(./deploy-fsuite.sh bertta22) timeout: 10m 0s
  ⎿  [INFO] Checking connectivity to bertta22...
     [OK] Connected to bertta22
     [OK] Found fsuite package: /home/player2vscpu/Desktop/agent/fsuite/fsuite_1.3.0_amd64.deb
     [WARN] tree package not found: /home/player2vscpu/Desktop/agent/fsuite/../tree_2.1.0-1_amd64.deb (may already be installed)

     [INFO] ╔═══════════════════════════════════════════════════════════╗
     [INFO] ║  fsuite Deployment to bertta22
     [INFO] ╚═══════════════════════════════════════════════════════════╝

     [INFO] === Deploying to bertta22 ===
     [INFO] fsuite 1.3.0 already installed on bertta22
     [OK] bertta22 already has fsuite 1.3.0

     [INFO] Getting RADi list from bertta22...
       Found: radi62 (10.11.47.185)
       Found: radi56 (10.11.54.13)
       Found: radi78 (10.11.47.201)
       Found: radi81 (10.11.217.156)
       Found: radi201 (10.11.130.7)
       Found: radi200 (10.11.130.6)
       Found: radi199 (10.11.130.5)

     [INFO] Deploying to RADis (sequentially for safety)...

     [INFO] ─── radi62 (10.11.47.185) [1/7] ───
     [INFO] Deploying SSH keys to radi62 (10.11.47.185)...
     [OK]   bertta22 key already on radi62
     [INFO]   Deploying local key to radi62...
     [INFO] Deploying fsuite to radi62...
     [OK]   radi62 already has fsuite 1.3.0
     [OK]   SSH config entry for radi62 already exists

     [INFO] ─── radi56 (10.11.54.13) [2/7] ───
     [INFO] Deploying SSH keys to radi56 (10.11.54.13)...
     [INFO]   Deploying bertta22 key to radi56...

     Number of key(s) added: 1

     Now try logging into the machine, with:   "ssh -o 'StrictHostKeyChecking=no' 'fusion@10.11.54.13'"
     and check to make sure that only the key(s) you wanted were added.

     [INFO]   Deploying local key to radi56...
     [INFO] Deploying fsuite to radi56...
     [INFO]   Installing fsuite on radi56...
     [sudo] password for fusion: Selecting previously unselected package fsuite.
     (Reading database ... 130515 files and directories currently installed.)
     Preparing to unpack .../bertta/fsuite_1.3.0_amd64.deb ...
     Unpacking fsuite (1.3.0) ...
     Setting up fsuite (1.3.0) ...

     ╔══════════════════════════════════════════════════════════════╗
     ║  fsuite 1.3.0 installed successfully!                        ║
     ╠══════════════════════════════════════════════════════════════╣
     ║  Filesystem Tools:                                           ║
     ║    ftree    - Directory structure + recon                    ║
     ║    fsearch  - Find files by name/pattern                     ║
     ║    fcontent - Search inside files                            ║
     ║                                                              ║
     ║  Log Analysis (NEW):                                         ║
     ║    flog     - Socket logger with clean output                ║
     ║                                                              ║
     ║  Quick start:                                                ║
     ║    ftree --snapshot /path/to/project                         ║
     ║    flog snapshot 50              # Last 50 filtered lines    ║
     ║    flog errors 20                # Last 20 errors            ║
     ║    flog tail                     # Live stream               ║
     ║    flog tower                    # Light tower status        ║
     ║                                                              ║
     ║  Docs: /usr/share/doc/fsuite/                                ║
     ╚══════════════════════════════════════════════════════════════╝

     [OK]   fsuite installed on radi56
     [INFO]   Adding radi56 to SSH config...
     [OK]   Added radi56 to SSH config

     [INFO] ─── radi78 (10.11.47.201) [3/7] ───
     [INFO] Deploying SSH keys to radi78 (10.11.47.201)...
     [INFO]   Deploying bertta22 key to radi78...

     Number of key(s) added: 1

     Now try logging into the machine, with:   "ssh -o 'StrictHostKeyChecking=no' 'fusion@10.11.47.201'"
     and check to make sure that only the key(s) you wanted were added.

     [INFO]   Deploying local key to radi78...
     [INFO] Deploying fsuite to radi78...
     [INFO]   Installing fsuite on radi78...
     [sudo] password for fusion: Selecting previously unselected package fsuite.
     (Reading database ... 126813 files and directories currently installed.)
     Preparing to unpack .../bertta/fsuite_1.3.0_amd64.deb ...
     Unpacking fsuite (1.3.0) ...
     Setting up fsuite (1.3.0) ...

     ╔══════════════════════════════════════════════════════════════╗
     ║  fsuite 1.3.0 installed successfully!                        ║
     ╠══════════════════════════════════════════════════════════════╣
     ║  Filesystem Tools:                                           ║
     ║    ftree    - Directory structure + recon                    ║
     ║    fsearch  - Find files by name/pattern                     ║
     ║    fcontent - Search inside files                            ║
     ║                                                              ║
     ║  Log Analysis (NEW):                                         ║
     ║    flog     - Socket logger with clean output                ║
     ║                                                              ║
     ║  Quick start:                                                ║
     ║    ftree --snapshot /path/to/project                         ║
     ║    flog snapshot 50              # Last 50 filtered lines    ║
     ║    flog errors 20                # Last 20 errors            ║
     ║    flog tail                     # Live stream               ║
     ║    flog tower                    # Light tower status        ║
     ║                                                              ║
     ║  Docs: /usr/share/doc/fsuite/                                ║
     ╚══════════════════════════════════════════════════════════════╝

     [OK]   fsuite installed on radi78
     [INFO]   Adding radi78 to SSH config...
     [OK]   Added radi78 to SSH config

     [INFO] ─── radi81 (10.11.217.156) [4/7] ───
     [INFO] Deploying SSH keys to radi81 (10.11.217.156)...
     [INFO]   Deploying bertta22 key to radi81...

     Number of key(s) added: 1

     Now try logging into the machine, with:   "ssh -o 'StrictHostKeyChecking=no' 'fusion@10.11.217.156'"
     and check to make sure that only the key(s) you wanted were added.

     [INFO]   Deploying local key to radi81...
     [INFO] Deploying fsuite to radi81...
     [INFO]   Installing fsuite on radi81...
     [sudo] password for fusion: Selecting previously unselected package fsuite.
     (Reading database ... 126704 files and directories currently installed.)
     Preparing to unpack .../bertta/fsuite_1.3.0_amd64.deb ...
     Unpacking fsuite (1.3.0) ...
     Setting up fsuite (1.3.0) ...

     ╔══════════════════════════════════════════════════════════════╗
     ║  fsuite 1.3.0 installed successfully!                        ║
     ╠══════════════════════════════════════════════════════════════╣
     ║  Filesystem Tools:                                           ║
     ║    ftree    - Directory structure + recon                    ║
     ║    fsearch  - Find files by name/pattern                     ║
     ║    fcontent - Search inside files                            ║
     ║                                                              ║
     ║  Log Analysis (NEW):                                         ║
     ║    flog     - Socket logger with clean output                ║
     ║                                                              ║
     ║  Quick start:                                                ║
     ║    ftree --snapshot /path/to/project                         ║
     ║    flog snapshot 50              # Last 50 filtered lines    ║
     ║    flog errors 20                # Last 20 errors            ║
     ║    flog tail                     # Live stream               ║
     ║    flog tower                    # Light tower status        ║
     ║                                                              ║
     ║  Docs: /usr/share/doc/fsuite/                                ║
     ╚══════════════════════════════════════════════════════════════╝

     [OK]   fsuite installed on radi81
     [INFO]   Adding radi81 to SSH config...
     [OK]   Added radi81 to SSH config

     [INFO] ─── radi201 (10.11.130.7) [5/7] ───
     [INFO] Deploying SSH keys to radi201 (10.11.130.7)...
     [INFO]   Deploying bertta22 key to radi201...

     Number of key(s) added: 1

     Now try logging into the machine, with:   "ssh -o 'StrictHostKeyChecking=no' 'fusion@10.11.130.7'"
     and check to make sure that only the key(s) you wanted were added.

     [INFO]   Deploying local key to radi201...
     [INFO] Deploying fsuite to radi201...
     [INFO]   Installing fsuite on radi201...
     [sudo] password for fusion: Selecting previously unselected package fsuite.
     (Reading database ... 125273 files and directories currently installed.)
     Preparing to unpack .../bertta/fsuite_1.3.0_amd64.deb ...
     Unpacking fsuite (1.3.0) ...
     Setting up fsuite (1.3.0) ...

     ╔══════════════════════════════════════════════════════════════╗
     ║  fsuite 1.3.0 installed successfully!                        ║
     ╠══════════════════════════════════════════════════════════════╣
     ║  Filesystem Tools:                                           ║
     ║    ftree    - Directory structure + recon                    ║
     ║    fsearch  - Find files by name/pattern                     ║
     ║    fcontent - Search inside files                            ║
     ║                                                              ║
     ║  Log Analysis (NEW):                                         ║
     ║    flog     - Socket logger with clean output                ║
     ║                                                              ║
     ║  Quick start:                                                ║
     ║    ftree --snapshot /path/to/project                         ║
     ║    flog snapshot 50              # Last 50 filtered lines    ║
     ║    flog errors 20                # Last 20 errors            ║
     ║    flog tail                     # Live stream               ║
     ║    flog tower                    # Light tower status        ║
     ║                                                              ║
     ║  Docs: /usr/share/doc/fsuite/                                ║
     ╚══════════════════════════════════════════════════════════════╝

     [OK]   fsuite installed on radi201
     [INFO]   Adding radi201 to SSH config...
     [OK]   Added radi201 to SSH config

     [INFO] ─── radi200 (10.11.130.6) [6/7] ───
     [INFO] Deploying SSH keys to radi200 (10.11.130.6)...
     [INFO]   Deploying bertta22 key to radi200...

     Number of key(s) added: 1

     Now try logging into the machine, with:   "ssh -o 'StrictHostKeyChecking=no' 'fusion@10.11.130.6'"
     and check to make sure that only the key(s) you wanted were added.

     [INFO]   Deploying local key to radi200...
     [INFO] Deploying fsuite to radi200...
     [INFO]   Installing fsuite on radi200...
     [sudo] password for fusion: Selecting previously unselected package fsuite.
     (Reading database ... 125273 files and directories currently installed.)
     Preparing to unpack .../bertta/fsuite_1.3.0_amd64.deb ...
     Unpacking fsuite (1.3.0) ...
     Setting up fsuite (1.3.0) ...

     ╔══════════════════════════════════════════════════════════════╗
     ║  fsuite 1.3.0 installed successfully!                        ║
     ╠══════════════════════════════════════════════════════════════╣
     ║  Filesystem Tools:                                           ║
     ║    ftree    - Directory structure + recon                    ║
     ║    fsearch  - Find files by name/pattern                     ║
     ║    fcontent - Search inside files                            ║
     ║                                                              ║
     ║  Log Analysis (NEW):                                         ║
     ║    flog     - Socket logger with clean output                ║
     ║                                                              ║
     ║  Quick start:                                                ║
     ║    ftree --snapshot /path/to/project                         ║
     ║    flog snapshot 50              # Last 50 filtered lines    ║
     ║    flog errors 20                # Last 20 errors            ║
     ║    flog tail                     # Live stream               ║
     ║    flog tower                    # Light tower status        ║
     ║                                                              ║
     ║  Docs: /usr/share/doc/fsuite/                                ║
     ╚══════════════════════════════════════════════════════════════╝

     [OK]   fsuite installed on radi200
     [INFO]   Adding radi200 to SSH config...
     [OK]   Added radi200 to SSH config

     [INFO] ─── radi199 (10.11.130.5) [7/7] ───
     [INFO] Deploying SSH keys to radi199 (10.11.130.5)...
     [INFO]   Deploying bertta22 key to radi199...

     Number of key(s) added: 1

     Now try logging into the machine, with:   "ssh -o 'StrictHostKeyChecking=no' 'fusion@10.11.130.5'"
     and check to make sure that only the key(s) you wanted were added.

     [INFO]   Deploying local key to radi199...
     [INFO] Deploying fsuite to radi199...
     [INFO]   Installing fsuite on radi199...
     [sudo] password for fusion: Selecting previously unselected package fsuite.
     (Reading database ... 125363 files and directories currently installed.)
     Preparing to unpack .../bertta/fsuite_1.3.0_amd64.deb ...
     Unpacking fsuite (1.3.0) ...
     Setting up fsuite (1.3.0) ...

     ╔══════════════════════════════════════════════════════════════╗
     ║  fsuite 1.3.0 installed successfully!                        ║
     ╠══════════════════════════════════════════════════════════════╣
     ║  Filesystem Tools:                                           ║
     ║    ftree    - Directory structure + recon                    ║
     ║    fsearch  - Find files by name/pattern                     ║
     ║    fcontent - Search inside files                            ║
     ║                                                              ║
     ║  Log Analysis (NEW):                                         ║
     ║    flog     - Socket logger with clean output                ║
     ║                                                              ║
     ║  Quick start:                                                ║
     ║    ftree --snapshot /path/to/project                         ║
     ║    flog snapshot 50              # Last 50 filtered lines    ║
     ║    flog errors 20                # Last 20 errors            ║
     ║    flog tail                     # Live stream               ║
     ║    flog tower                    # Light tower status        ║
     ║                                                              ║
     ║  Docs: /usr/share/doc/fsuite/                                ║
     ╚══════════════════════════════════════════════════════════════╝

     [OK]   fsuite installed on radi199
     [INFO]   Adding radi199 to SSH config...
     [OK]   Added radi199 to SSH config

     [INFO] ╔═══════════════════════════════════════════════════════════╗
     [INFO] ║  Deployment Complete!                                      ║
     [INFO] ╚═══════════════════════════════════════════════════════════╝

     [INFO] Test with:
       ssh <radi_name> 'flog tower'
```
