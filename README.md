# TurboFox

TurboFox is an in memory kv store written in pure x86_64 Assembly.

## Setup

- Install using bash script,

 ```bash
 curl -fsSL https://raw.githubusercontent.com/frozen-lab/turbofox/master/install.sh | bash
 ```
- Start the server,
  
```bash
.local/bin/turbofox
```

## Benchmark

- **Machine Type**: GCP Compute Engine `e2-micro` (2 vCPUs, 1 GB memory)
- **CPU Platform**: Intel Broadwell
- **Architecture**: x86/64

| Command | Total Time (ms) | Operations per Second (ops/sec) | Average Time per Operation (ms/op) |
|:-------:|:---------------:|:-------------------------------:|:----------------------------------:|
| `SET`   | 61446.24         | 1.63                            | 614.46                             |
| `GET`   | 61502.91         | 1.63                            | 615.03                             |
| `DEL`   | 61888.38         | 1.62                            | 618.88                             |

