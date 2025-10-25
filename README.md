# Belief Explorer

A web-based belief analysis platform with FPGA-accelerated multi-base optimization for trading applications.

## Projects

This repository contains two main projects:

### 1. Belief Explorer (Web Application)

A web-based platform for analyzing beliefs, claims, and perspectives using AI-powered analysis.

**Features:**
- Interactive chat interface
- Critical thinking analysis
- Multiple perspective evaluation
- Advanced metrics (Verifact Score, MDQ, CSI, etc.)
- Responsive design with dark mode

**Files:**
- `index.html` - Main application
- `privacy.html` - Privacy policy

**Usage:**
Open `index.html` in a web browser or deploy to a web server.

---

### 2. Multi-Base HFT Optimizer (FPGA)

An FPGA-accelerated trading optimizer using adaptive base arithmetic (base 12, 10, 2) for high-frequency and mid-frequency trading.

**Features:**
- Multi-base arithmetic optimization (base 12/10/2)
- FPGA acceleration on Xilinx PYNQ Z2
- Sub-100ns latency for trading decisions
- Built-in trading strategies (market making, mean reversion, momentum, arbitrage)
- Python PYNQ interface
- Real-time performance monitoring

**Documentation:**
See [docs/README_OPTIMIZER.md](docs/README_OPTIMIZER.md) for complete documentation.

**Quick Start:**

```bash
# Build FPGA bitstream
cd fpga/scripts
vivado -mode batch -source build_vivado.tcl

# Deploy to PYNQ Z2
scp output/multi_base_optimizer.bit xilinx@pynq-z2:/home/xilinx/

# Run optimizer (on PYNQ board)
python3 pynq_optimizer_driver.py
```

**Architecture:**

```
belief-explorer/
├── index.html                    # Web application
├── privacy.html
├── fpga/                         # FPGA implementation
│   ├── verilog/                  # RTL sources
│   │   ├── base_converter.v      # Multi-base converter
│   │   ├── hft_optimizer_core.v  # Trading optimizer
│   │   └── pynq_z2_top.v         # Top-level module
│   ├── constraints/              # FPGA constraints
│   │   └── pynq_z2_constraints.xdc
│   ├── scripts/                  # Build scripts
│   │   └── build_vivado.tcl      # Vivado build automation
│   └── python/                   # PYNQ Python interface
│       └── pynq_optimizer_driver.py
├── backend/                      # Backend services
│   └── optimizer_service/
│       ├── optimizer/
│       │   └── multi_base_optimizer.py  # CPU optimizer
│       └── models/
│           └── hft_strategies.py        # Trading strategies
├── docs/                         # Documentation
│   └── README_OPTIMIZER.md       # Optimizer documentation
└── README.md                     # This file
```

## Performance Highlights

### Multi-Base Optimizer

| Metric | Value |
|--------|-------|
| Latency | < 100ns (FPGA) |
| Throughput | 800,000+ ops/sec |
| Base-12 Advantage | 15-30% cycle reduction |
| FPGA Utilization | ~15% LUTs, ~9% FFs |

## Technologies

**Web Application:**
- HTML5, CSS3, JavaScript
- Chart.js for visualizations
- N8N webhook integration

**FPGA Optimizer:**
- Verilog HDL
- Xilinx Vivado
- PYNQ framework
- Python 3.7+
- NumPy, SciPy

## Getting Started

### Belief Explorer

Simply open `index.html` in a web browser.

### FPGA Optimizer

See [docs/README_OPTIMIZER.md](docs/README_OPTIMIZER.md) for detailed instructions.

**Prerequisites:**
- Xilinx PYNQ Z2 board
- Vivado 2020.1+
- PYNQ 2.7+

## Use Cases

### Belief Explorer
- Critical thinking development
- Argument analysis
- Multi-perspective evaluation
- Educational applications

### FPGA Optimizer
- High-frequency trading (HFT)
- Mid-frequency trading
- Algorithmic trading research
- FPGA acceleration studies
- Multi-base arithmetic research

## Documentation

- [FPGA Optimizer README](docs/README_OPTIMIZER.md) - Complete optimizer documentation
- [Privacy Policy](privacy.html) - Belief Explorer privacy policy

## Development

### Directory Structure

- `/` - Web application files
- `/fpga/` - FPGA implementation
- `/backend/` - Backend services and algorithms
- `/docs/` - Documentation
- `/config/` - Configuration files

### Building from Source

**FPGA Bitstream:**
```bash
cd fpga/scripts
vivado -mode batch -source build_vivado.tcl
```

**Python Optimizer (CPU):**
```bash
cd backend/optimizer_service
python optimizer/multi_base_optimizer.py
```

**Trading Strategies:**
```bash
cd backend/optimizer_service
python models/hft_strategies.py
```

## Testing

### FPGA Optimizer Tests

```python
# Run simulation mode (no FPGA required)
from fpga.python.pynq_optimizer_driver import MultiBaseOptimizer

optimizer = MultiBaseOptimizer()  # Simulation mode
result = optimizer.optimize(
    bid_price=100.25,
    ask_price=100.28,
    last_price=100.26,
    bid_size=1000,
    ask_size=1200
)
print(result)

# Run benchmark
bench = optimizer.benchmark(iterations=100)
print(f"Throughput: {bench['throughput_ops_per_sec']:.0f} ops/sec")
```

## Contributing

Contributions are welcome! Areas of interest:

**Belief Explorer:**
- New analysis metrics
- UI/UX improvements
- Additional visualizations

**FPGA Optimizer:**
- Additional trading strategies
- Performance optimizations
- Support for other FPGA boards
- Machine learning integration

## License

See individual project files for licensing information.

## Disclaimer

**FPGA Optimizer:** This software is for educational and research purposes only. Use in production trading systems requires extensive testing, validation, and risk management. The authors are not responsible for financial losses.

## Acknowledgments

- Xilinx for PYNQ framework
- The Dozenal Society for base-12 research
- Open-source FPGA community

## Contact

For questions or issues, please open an issue on GitHub.

---

**Status:** Active Development
**Last Updated:** 2025-10-25
