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

- **Server Machine**: GCP Compute Engine (`asia-southeast1-b / e2-micro`) (2 vCPUs, 1 GB memory)
- **Client Machine**: GCP Cloud Shell (`asia-southeast1-b`) 
- **CPU Platform**: Intel Broadwell
- **Architecture**: x86/64
- **Connection Pool Size**: 1000

| Command | Total Time (ms) | Operations per Second (ops/sec) | Average Time per Operation (ms/op) |
|:-------:|:---------------:|:-------------------------------:|:----------------------------------:|
| `SET`   | 4961.41         | 201.56                         | 4.96                               |
| `GET`   | 5144.92         | 194.37                         | 5.14                               |
| `DEL`   | 6180.53         | 161.80                         | 6.18                               |

