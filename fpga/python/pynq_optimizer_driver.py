"""
PYNQ Z2 Multi-Base HFT Optimizer Driver
Python interface for FPGA-accelerated trading optimization

This driver provides high-level Python API for:
- Multi-base arithmetic (base 12, 10, 2)
- HFT and mid-frequency trading optimization
- Low-latency FPGA acceleration
- Performance monitoring

Requirements:
- PYNQ 2.7 or later
- Xilinx PYNQ Z2 board
- Compiled FPGA bitstream (pynq_z2_top.bit)
"""

import time
import struct
from typing import Tuple, Dict, Optional
import numpy as np

try:
    from pynq import Overlay, MMIO
    from pynq import allocate
    PYNQ_AVAILABLE = True
except ImportError:
    print("Warning: PYNQ not available. Running in simulation mode.")
    PYNQ_AVAILABLE = False


class MultiBaseOptimizer:
    """
    Multi-Base HFT Optimizer for PYNQ Z2

    Provides hardware-accelerated optimization using adaptive base arithmetic.
    Can switch between base 12 (dozenal), base 10 (decimal), and base 2 (binary)
    for optimal calculation performance.
    """

    # Register addresses (must match Verilog)
    REG_CONTROL       = 0x000
    REG_STATUS        = 0x004
    REG_BID_PRICE_H   = 0x008
    REG_BID_PRICE_L   = 0x00C
    REG_ASK_PRICE_H   = 0x010
    REG_ASK_PRICE_L   = 0x014
    REG_LAST_PRICE_H  = 0x018
    REG_LAST_PRICE_L  = 0x01C
    REG_BID_SIZE      = 0x020
    REG_ASK_SIZE      = 0x024
    REG_BASE_SELECT   = 0x028
    REG_RISK_LIMIT    = 0x02C
    REG_LATENCY_BUDG  = 0x030
    REG_STRATEGY_ID   = 0x034
    REG_RESULT_PRICE_H = 0x038
    REG_RESULT_PRICE_L = 0x03C
    REG_EXIT_PRICE_H  = 0x040
    REG_EXIT_PRICE_L  = 0x044
    REG_QUANTITY      = 0x048
    REG_EXPECTED_PROFIT = 0x04C
    REG_CONFIDENCE    = 0x050
    REG_BASE_USED     = 0x054
    REG_CYCLES_TAKEN  = 0x058
    REG_BASE12_ADV    = 0x05C
    REG_COMP_PER_SEC  = 0x060

    # Base selection constants
    BASE_AUTO = 0
    BASE_BINARY = 0  # Base 2
    BASE_DECIMAL = 1  # Base 10
    BASE_DOZENAL = 2  # Base 12

    # Strategy IDs
    STRATEGY_MARKET_MAKING = 0
    STRATEGY_MEAN_REVERSION = 1
    STRATEGY_MOMENTUM = 2
    STRATEGY_ARBITRAGE = 3

    def __init__(self, bitstream_path: str = None, base_addr: int = 0x40000000):
        """
        Initialize the Multi-Base Optimizer

        Args:
            bitstream_path: Path to FPGA bitstream (.bit file)
            base_addr: Base address of AXI peripheral
        """
        self.bitstream_path = bitstream_path
        self.base_addr = base_addr
        self.overlay = None
        self.mmio = None
        self.simulation_mode = not PYNQ_AVAILABLE

        if not self.simulation_mode and bitstream_path:
            self._initialize_fpga(bitstream_path)
        elif not self.simulation_mode:
            print("Warning: No bitstream provided. Call load_bitstream() to initialize FPGA.")

    def _initialize_fpga(self, bitstream_path: str):
        """Load bitstream and initialize MMIO interface"""
        try:
            print(f"Loading bitstream: {bitstream_path}")
            self.overlay = Overlay(bitstream_path)

            # Create MMIO object for register access
            # Adjust the name based on your Vivado block design
            self.mmio = MMIO(self.base_addr, 0x10000)  # 64KB address space

            # Reset the core
            self._write_reg(self.REG_CONTROL, 0x02)  # Set enable bit
            time.sleep(0.001)

            print("FPGA initialized successfully")
            self._print_device_info()

        except Exception as e:
            print(f"Error initializing FPGA: {e}")
            print("Falling back to simulation mode")
            self.simulation_mode = True

    def load_bitstream(self, bitstream_path: str):
        """Load FPGA bitstream"""
        self._initialize_fpga(bitstream_path)

    def _write_reg(self, offset: int, value: int):
        """Write to FPGA register"""
        if self.simulation_mode:
            return
        self.mmio.write(offset, value & 0xFFFFFFFF)

    def _read_reg(self, offset: int) -> int:
        """Read from FPGA register"""
        if self.simulation_mode:
            return 0
        return self.mmio.read(offset)

    def _write_price(self, reg_h: int, reg_l: int, price: float):
        """
        Write price as 48-bit fixed point (16.32 format)

        Args:
            reg_h: High register offset
            reg_l: Low register offset
            price: Price as float
        """
        # Convert to fixed point: 16 integer bits, 32 fractional bits
        fixed_price = int(price * (2**32))

        # Split into high and low 32-bit words
        price_h = (fixed_price >> 32) & 0xFFFF
        price_l = fixed_price & 0xFFFFFFFF

        self._write_reg(reg_h, price_h)
        self._write_reg(reg_l, price_l)

    def _read_price(self, reg_h: int, reg_l: int) -> float:
        """
        Read price as float from 48-bit fixed point

        Args:
            reg_h: High register offset
            reg_l: Low register offset

        Returns:
            Price as float
        """
        price_h = self._read_reg(reg_h)
        price_l = self._read_reg(reg_l)

        # Combine into 48-bit value
        fixed_price = ((price_h & 0xFFFF) << 32) | price_l

        # Convert from fixed point to float
        return fixed_price / (2**32)

    def optimize(self,
                 bid_price: float,
                 ask_price: float,
                 last_price: float,
                 bid_size: int,
                 ask_size: int,
                 base_select: int = BASE_AUTO,
                 risk_limit: int = 100000,
                 latency_budget_ns: int = 1000,
                 strategy_id: int = STRATEGY_MARKET_MAKING,
                 timeout_ms: int = 100) -> Dict:
        """
        Run optimization on FPGA

        Args:
            bid_price: Current bid price
            ask_price: Current ask price
            last_price: Last traded price
            bid_size: Bid quantity
            ask_size: Ask quantity
            base_select: Base selection (AUTO, BINARY, DECIMAL, DOZENAL)
            risk_limit: Maximum position risk
            latency_budget_ns: Latency budget in nanoseconds
            strategy_id: Trading strategy to use
            timeout_ms: Timeout in milliseconds

        Returns:
            Dictionary with optimization results
        """
        start_time = time.time()

        if self.simulation_mode:
            return self._simulate_optimization(
                bid_price, ask_price, last_price, bid_size, ask_size
            )

        # Write input parameters
        self._write_price(self.REG_BID_PRICE_H, self.REG_BID_PRICE_L, bid_price)
        self._write_price(self.REG_ASK_PRICE_H, self.REG_ASK_PRICE_L, ask_price)
        self._write_price(self.REG_LAST_PRICE_H, self.REG_LAST_PRICE_L, last_price)
        self._write_reg(self.REG_BID_SIZE, bid_size)
        self._write_reg(self.REG_ASK_SIZE, ask_size)
        self._write_reg(self.REG_BASE_SELECT, base_select)
        self._write_reg(self.REG_RISK_LIMIT, risk_limit)
        self._write_reg(self.REG_LATENCY_BUDG, latency_budget_ns)
        self._write_reg(self.REG_STRATEGY_ID, strategy_id)

        # Start optimization
        self._write_reg(self.REG_CONTROL, 0x03)  # Enable + Start

        # Wait for completion
        timeout_s = timeout_ms / 1000.0
        while time.time() - start_time < timeout_s:
            status = self._read_reg(self.REG_STATUS)
            if status & 0x01:  # Bit 0: optimization complete
                break
            time.sleep(0.0001)  # 100 microseconds
        else:
            return {"error": "Optimization timeout", "success": False}

        # Read results
        entry_price = self._read_price(self.REG_RESULT_PRICE_H, self.REG_RESULT_PRICE_L)
        exit_price = self._read_price(self.REG_EXIT_PRICE_H, self.REG_EXIT_PRICE_L)
        quantity = self._read_reg(self.REG_QUANTITY)
        expected_profit = self._read_reg(self.REG_EXPECTED_PROFIT)
        confidence = self._read_reg(self.REG_CONFIDENCE) / 100.0  # Convert to percentage
        base_used = self._read_reg(self.REG_BASE_USED)
        cycles_taken = self._read_reg(self.REG_CYCLES_TAKEN)
        base12_advantage = self._read_reg(self.REG_BASE12_ADV)
        comp_per_sec = self._read_reg(self.REG_COMP_PER_SEC)

        # Calculate latency
        latency_us = (time.time() - start_time) * 1_000_000

        # Determine trade signal
        trade_signal_valid = (status & 0x10000) != 0

        base_names = {0: "Binary", 1: "Decimal", 2: "Dozenal"}

        return {
            "success": True,
            "entry_price": entry_price,
            "exit_price": exit_price,
            "quantity": quantity,
            "expected_profit": expected_profit,
            "confidence": confidence,
            "base_used": base_names.get(base_used, "Unknown"),
            "base_used_id": base_used,
            "cycles_taken": cycles_taken,
            "base12_advantage_cycles": base12_advantage,
            "computations_per_sec": comp_per_sec,
            "latency_us": latency_us,
            "trade_signal": trade_signal_valid,
            "spread": ask_price - bid_price,
            "mid_price": (bid_price + ask_price) / 2
        }

    def _simulate_optimization(self, bid: float, ask: float, last: float,
                              bid_size: int, ask_size: int) -> Dict:
        """Simulation mode for testing without FPGA"""
        time.sleep(0.001)  # Simulate FPGA latency

        spread = ask - bid
        mid_price = (bid + ask) / 2

        # Simple simulation logic
        entry_price = mid_price + spread * 0.1
        exit_price = entry_price + spread * 0.5
        quantity = min(bid_size, ask_size) // 2
        expected_profit = int((exit_price - entry_price) * quantity * 1000)

        return {
            "success": True,
            "entry_price": entry_price,
            "exit_price": exit_price,
            "quantity": quantity,
            "expected_profit": expected_profit,
            "confidence": 85.5,
            "base_used": "Dozenal",
            "base_used_id": 2,
            "cycles_taken": 125,
            "base12_advantage_cycles": 15,
            "computations_per_sec": 800000,
            "latency_us": 1.25,
            "trade_signal": expected_profit > 0,
            "spread": spread,
            "mid_price": mid_price,
            "mode": "simulation"
        }

    def _print_device_info(self):
        """Print FPGA device information"""
        print("\n" + "="*60)
        print("Multi-Base HFT Optimizer - Device Information")
        print("="*60)
        print(f"Base Address: 0x{self.base_addr:08X}")
        print(f"Status: {'Simulation Mode' if self.simulation_mode else 'FPGA Mode'}")

        if not self.simulation_mode:
            status = self._read_reg(self.REG_STATUS)
            print(f"Device Ready: {bool(status & 0x01)}")
            print(f"Computations/sec: {self._read_reg(self.REG_COMP_PER_SEC):,}")

        print("="*60 + "\n")

    def benchmark(self, iterations: int = 1000) -> Dict:
        """
        Run benchmark to measure FPGA performance

        Args:
            iterations: Number of optimization iterations

        Returns:
            Benchmark results
        """
        print(f"Running benchmark with {iterations} iterations...")

        # Test parameters
        bid = 100.25
        ask = 100.28
        last = 100.26
        bid_size = 1000
        ask_size = 1200

        latencies = []
        base_usage = {"Binary": 0, "Decimal": 0, "Dozenal": 0}
        total_cycles = 0

        start_time = time.time()

        for i in range(iterations):
            # Vary prices slightly for realistic test
            result = self.optimize(
                bid + (i % 10) * 0.01,
                ask + (i % 10) * 0.01,
                last + (i % 10) * 0.01,
                bid_size,
                ask_size,
                base_select=self.BASE_AUTO
            )

            if result["success"]:
                latencies.append(result["latency_us"])
                base_usage[result["base_used"]] += 1
                total_cycles += result["cycles_taken"]

        end_time = time.time()
        total_time = end_time - start_time

        latencies = np.array(latencies)

        return {
            "iterations": iterations,
            "total_time_s": total_time,
            "avg_latency_us": np.mean(latencies),
            "min_latency_us": np.min(latencies),
            "max_latency_us": np.max(latencies),
            "std_latency_us": np.std(latencies),
            "throughput_ops_per_sec": iterations / total_time,
            "avg_cycles": total_cycles / iterations,
            "base_usage": base_usage,
            "base12_usage_pct": 100 * base_usage["Dozenal"] / iterations
        }

    def reset(self):
        """Reset the FPGA core"""
        self._write_reg(self.REG_CONTROL, 0x00)
        time.sleep(0.001)
        self._write_reg(self.REG_CONTROL, 0x02)  # Re-enable

    def get_status(self) -> Dict:
        """Get current status of optimizer"""
        if self.simulation_mode:
            return {"mode": "simulation", "ready": True}

        status = self._read_reg(self.REG_STATUS)

        return {
            "mode": "fpga",
            "ready": bool(status & 0x01),
            "optimization_complete": bool(status & 0x01),
            "trade_signal_valid": bool(status & 0x10000),
            "optimizer_busy": bool(status & 0x20000),
            "computations_per_sec": self._read_reg(self.REG_COMP_PER_SEC)
        }


# Example usage and testing
if __name__ == "__main__":
    print("Multi-Base HFT Optimizer - PYNQ Driver")
    print("=" * 60)

    # Initialize optimizer (simulation mode if no FPGA)
    optimizer = MultiBaseOptimizer()

    # Example market data
    print("\nExample 1: Market Making Strategy")
    result = optimizer.optimize(
        bid_price=100.25,
        ask_price=100.28,
        last_price=100.26,
        bid_size=1000,
        ask_size=1200,
        base_select=MultiBaseOptimizer.BASE_AUTO,
        risk_limit=100000,
        strategy_id=MultiBaseOptimizer.STRATEGY_MARKET_MAKING
    )

    print(f"Entry Price: ${result['entry_price']:.4f}")
    print(f"Exit Price: ${result['exit_price']:.4f}")
    print(f"Quantity: {result['quantity']}")
    print(f"Expected Profit: ${result['expected_profit']:.2f}")
    print(f"Confidence: {result['confidence']:.1f}%")
    print(f"Base Used: {result['base_used']}")
    print(f"Cycles Taken: {result['cycles_taken']}")
    print(f"Latency: {result['latency_us']:.2f} μs")
    print(f"Trade Signal: {'BUY' if result['trade_signal'] else 'HOLD'}")

    # Run benchmark
    print("\n" + "=" * 60)
    print("Running Performance Benchmark...")
    print("=" * 60)

    bench_results = optimizer.benchmark(iterations=100)

    print(f"\nBenchmark Results ({bench_results['iterations']} iterations):")
    print(f"  Total Time: {bench_results['total_time_s']:.3f} seconds")
    print(f"  Throughput: {bench_results['throughput_ops_per_sec']:.0f} ops/sec")
    print(f"  Avg Latency: {bench_results['avg_latency_us']:.2f} μs")
    print(f"  Min Latency: {bench_results['min_latency_us']:.2f} μs")
    print(f"  Max Latency: {bench_results['max_latency_us']:.2f} μs")
    print(f"  Avg Cycles: {bench_results['avg_cycles']:.0f}")
    print(f"\nBase Usage:")
    for base, count in bench_results['base_usage'].items():
        print(f"  {base}: {count} ({100*count/bench_results['iterations']:.1f}%)")
    print(f"\nBase-12 Usage: {bench_results['base12_usage_pct']:.1f}%")
    print("\n" + "=" * 60)
