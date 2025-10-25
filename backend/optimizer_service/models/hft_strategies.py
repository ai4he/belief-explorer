"""
HFT and Mid-Frequency Trading Strategies
Optimized for FPGA execution with multi-base arithmetic

Strategies:
1. Market Making - Provide liquidity and capture spread
2. Mean Reversion - Trade on price deviations from mean
3. Momentum - Follow trending price movements
4. Statistical Arbitrage - Exploit price inefficiencies
"""

import numpy as np
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass
from enum import Enum


class SignalType(Enum):
    """Trading signal types"""
    BUY = 1
    SELL = -1
    HOLD = 0


class StrategyType(Enum):
    """Available trading strategies"""
    MARKET_MAKING = 0
    MEAN_REVERSION = 1
    MOMENTUM = 2
    ARBITRAGE = 3


@dataclass
class MarketData:
    """Market data snapshot"""
    timestamp: float
    bid_price: float
    ask_price: float
    last_price: float
    bid_size: int
    ask_size: int
    volume: int = 0
    vwap: float = 0.0  # Volume Weighted Average Price


@dataclass
class TradingSignal:
    """Trading signal output"""
    signal: SignalType
    entry_price: float
    exit_price: float
    quantity: int
    confidence: float  # 0-100
    expected_profit: float
    risk_amount: float
    stop_loss: float
    take_profit: float
    reasoning: str


class MarketMakingStrategy:
    """
    Market Making Strategy

    Provides liquidity by placing limit orders on both sides of the book.
    Profits from bid-ask spread while managing inventory risk.

    Optimized for:
    - Base-12 arithmetic (spread divisions)
    - Ultra-low latency execution
    - Dynamic spread adjustment
    """

    def __init__(self,
                 min_spread_bps: float = 5.0,
                 max_position: int = 10000,
                 skew_factor: float = 0.5):
        """
        Initialize market making strategy

        Args:
            min_spread_bps: Minimum profitable spread in basis points
            max_position: Maximum position size
            skew_factor: Order placement skew (0.5 = centered)
        """
        self.min_spread_bps = min_spread_bps
        self.max_position = max_position
        self.skew_factor = skew_factor
        self.current_position = 0

    def generate_signal(self, market_data: MarketData) -> TradingSignal:
        """
        Generate market making signal

        Args:
            market_data: Current market data

        Returns:
            Trading signal
        """
        bid = market_data.bid_price
        ask = market_data.ask_price
        mid = (bid + ask) / 2
        spread = ask - bid
        spread_bps = (spread / mid) * 10000

        # Check if spread is profitable
        if spread_bps < self.min_spread_bps:
            return self._hold_signal(mid, "Spread too narrow")

        # Calculate optimal quote placement
        # Use base-12 divisions for efficiency
        bid_offset = spread / 12  # 1/12 of spread (dozenal advantage)
        ask_offset = spread * 11 / 12  # 11/12 of spread

        # Adjust for inventory skew
        inventory_skew = self.current_position / self.max_position
        bid_offset *= (1 + inventory_skew * self.skew_factor)
        ask_offset *= (1 - inventory_skew * self.skew_factor)

        # Entry prices
        bid_quote = bid + bid_offset
        ask_quote = ask - ask_offset

        # Determine signal based on inventory
        if self.current_position < self.max_position:
            signal = SignalType.BUY
            entry = bid_quote
            exit = ask_quote
        elif self.current_position > -self.max_position:
            signal = SignalType.SELL
            entry = ask_quote
            exit = bid_quote
        else:
            return self._hold_signal(mid, "Position limit reached")

        # Calculate metrics
        expected_profit = abs(exit - entry)
        quantity = min(market_data.bid_size, market_data.ask_size) // 4
        confidence = min(95.0, 50.0 + spread_bps * 5)

        return TradingSignal(
            signal=signal,
            entry_price=entry,
            exit_price=exit,
            quantity=quantity,
            confidence=confidence,
            expected_profit=expected_profit * quantity,
            risk_amount=spread * quantity,
            stop_loss=entry - spread if signal == SignalType.BUY else entry + spread,
            take_profit=exit,
            reasoning=f"Market making: spread={spread_bps:.1f}bps, inventory={self.current_position}"
        )

    def _hold_signal(self, price: float, reason: str) -> TradingSignal:
        """Generate hold signal"""
        return TradingSignal(
            signal=SignalType.HOLD,
            entry_price=price,
            exit_price=price,
            quantity=0,
            confidence=0.0,
            expected_profit=0.0,
            risk_amount=0.0,
            stop_loss=price,
            take_profit=price,
            reasoning=reason
        )


class MeanReversionStrategy:
    """
    Mean Reversion Strategy

    Trades based on statistical deviations from mean price.
    Uses Bollinger Bands and Z-score for signal generation.

    Optimized for:
    - Mid-frequency trading (seconds to minutes)
    - Statistical calculations in base-12
    - Volatility-adjusted sizing
    """

    def __init__(self,
                 lookback_periods: int = 20,
                 entry_z_score: float = 2.0,
                 exit_z_score: float = 0.5,
                 volatility_window: int = 20):
        """
        Initialize mean reversion strategy

        Args:
            lookback_periods: Periods for mean calculation
            entry_z_score: Z-score threshold for entry
            exit_z_score: Z-score threshold for exit
            volatility_window: Window for volatility calculation
        """
        self.lookback_periods = lookback_periods
        self.entry_z_score = entry_z_score
        self.exit_z_score = exit_z_score
        self.volatility_window = volatility_window
        self.price_history: List[float] = []

    def generate_signal(self,
                       market_data: MarketData,
                       price_history: Optional[List[float]] = None) -> TradingSignal:
        """
        Generate mean reversion signal

        Args:
            market_data: Current market data
            price_history: Historical prices

        Returns:
            Trading signal
        """
        current_price = market_data.last_price

        # Update price history
        if price_history is not None:
            self.price_history = price_history[-self.lookback_periods:]
        self.price_history.append(current_price)

        # Need sufficient history
        if len(self.price_history) < self.lookback_periods:
            return self._hold_signal(current_price, "Insufficient history")

        # Calculate statistics
        prices = np.array(self.price_history[-self.lookback_periods:])
        mean_price = np.mean(prices)
        std_price = np.std(prices)

        if std_price == 0:
            return self._hold_signal(current_price, "Zero volatility")

        # Calculate Z-score
        z_score = (current_price - mean_price) / std_price

        # Generate signal
        if z_score > self.entry_z_score:
            # Price too high, expect reversion down
            signal = SignalType.SELL
            entry = current_price
            exit = mean_price + self.exit_z_score * std_price
            confidence = min(95.0, abs(z_score) * 25)

        elif z_score < -self.entry_z_score:
            # Price too low, expect reversion up
            signal = SignalType.BUY
            entry = current_price
            exit = mean_price - self.exit_z_score * std_price
            confidence = min(95.0, abs(z_score) * 25)

        else:
            return self._hold_signal(current_price, f"Z-score {z_score:.2f} within threshold")

        # Calculate position size based on volatility
        # Use base-12 divisions for efficiency
        volatility_adj = 1.0 / (1.0 + std_price / mean_price)
        base_quantity = 1000
        quantity = int(base_quantity * volatility_adj)

        expected_profit = abs(exit - entry) * quantity
        risk_amount = 2 * std_price * quantity

        return TradingSignal(
            signal=signal,
            entry_price=entry,
            exit_price=exit,
            quantity=quantity,
            confidence=confidence,
            expected_profit=expected_profit,
            risk_amount=risk_amount,
            stop_loss=entry - 3*std_price if signal == SignalType.BUY else entry + 3*std_price,
            take_profit=exit,
            reasoning=f"Mean reversion: z-score={z_score:.2f}, mean=${mean_price:.2f}, std=${std_price:.2f}"
        )

    def _hold_signal(self, price: float, reason: str) -> TradingSignal:
        """Generate hold signal"""
        return TradingSignal(
            signal=SignalType.HOLD,
            entry_price=price,
            exit_price=price,
            quantity=0,
            confidence=0.0,
            expected_profit=0.0,
            risk_amount=0.0,
            stop_loss=price,
            take_profit=price,
            reasoning=reason
        )


class MomentumStrategy:
    """
    Momentum Strategy

    Follows price trends using moving averages and RSI.
    Enters when momentum is strong, exits on reversal signals.

    Optimized for:
    - Fast trend detection
    - Binary operations (moving averages)
    - Low-latency execution
    """

    def __init__(self,
                 fast_period: int = 8,   # Base-2 for bit-shift optimization
                 slow_period: int = 16,  # Base-2 for bit-shift optimization
                 rsi_period: int = 14,
                 rsi_overbought: float = 70,
                 rsi_oversold: float = 30):
        """
        Initialize momentum strategy

        Args:
            fast_period: Fast moving average period
            slow_period: Slow moving average period
            rsi_period: RSI calculation period
            rsi_overbought: RSI overbought threshold
            rsi_oversold: RSI oversold threshold
        """
        self.fast_period = fast_period
        self.slow_period = slow_period
        self.rsi_period = rsi_period
        self.rsi_overbought = rsi_overbought
        self.rsi_oversold = rsi_oversold
        self.price_history: List[float] = []

    def generate_signal(self,
                       market_data: MarketData,
                       price_history: Optional[List[float]] = None) -> TradingSignal:
        """
        Generate momentum signal

        Args:
            market_data: Current market data
            price_history: Historical prices

        Returns:
            Trading signal
        """
        current_price = market_data.last_price

        # Update price history
        if price_history is not None:
            self.price_history = price_history[-self.slow_period:]
        self.price_history.append(current_price)

        # Need sufficient history
        if len(self.price_history) < self.slow_period:
            return self._hold_signal(current_price, "Insufficient history")

        # Calculate moving averages (optimized for base-2)
        prices = np.array(self.price_history)
        fast_ma = np.mean(prices[-self.fast_period:])
        slow_ma = np.mean(prices[-self.slow_period:])

        # Calculate RSI
        rsi = self._calculate_rsi(prices[-self.rsi_period:])

        # Generate signal based on MA crossover and RSI
        ma_bullish = fast_ma > slow_ma
        ma_bearish = fast_ma < slow_ma

        if ma_bullish and rsi < self.rsi_overbought:
            # Bullish momentum
            signal = SignalType.BUY
            entry = current_price
            # Exit at fast MA
            exit = fast_ma * 1.02  # 2% target
            confidence = min(95.0, 50 + (fast_ma - slow_ma) / slow_ma * 1000)

        elif ma_bearish and rsi > self.rsi_oversold:
            # Bearish momentum
            signal = SignalType.SELL
            entry = current_price
            exit = fast_ma * 0.98  # 2% target
            confidence = min(95.0, 50 + (slow_ma - fast_ma) / slow_ma * 1000)

        else:
            return self._hold_signal(current_price,
                                   f"No momentum: RSI={rsi:.1f}, FastMA={fast_ma:.2f}, SlowMA={slow_ma:.2f}")

        # Position sizing
        volatility = np.std(prices[-self.rsi_period:])
        quantity = int(10000 / (1 + volatility))

        expected_profit = abs(exit - entry) * quantity
        risk_amount = volatility * 2 * quantity

        return TradingSignal(
            signal=signal,
            entry_price=entry,
            exit_price=exit,
            quantity=quantity,
            confidence=confidence,
            expected_profit=expected_profit,
            risk_amount=risk_amount,
            stop_loss=entry - volatility*2 if signal == SignalType.BUY else entry + volatility*2,
            take_profit=exit,
            reasoning=f"Momentum: RSI={rsi:.1f}, Fast MA=${fast_ma:.2f}, Slow MA=${slow_ma:.2f}"
        )

    def _calculate_rsi(self, prices: np.ndarray) -> float:
        """Calculate RSI indicator"""
        if len(prices) < 2:
            return 50.0

        # Calculate price changes
        deltas = np.diff(prices)
        gains = np.where(deltas > 0, deltas, 0)
        losses = np.where(deltas < 0, -deltas, 0)

        avg_gain = np.mean(gains) if len(gains) > 0 else 0
        avg_loss = np.mean(losses) if len(losses) > 0 else 0

        if avg_loss == 0:
            return 100.0

        rs = avg_gain / avg_loss
        rsi = 100 - (100 / (1 + rs))

        return rsi

    def _hold_signal(self, price: float, reason: str) -> TradingSignal:
        """Generate hold signal"""
        return TradingSignal(
            signal=SignalType.HOLD,
            entry_price=price,
            exit_price=price,
            quantity=0,
            confidence=0.0,
            expected_profit=0.0,
            risk_amount=0.0,
            stop_loss=price,
            take_profit=price,
            reasoning=reason
        )


class StatisticalArbitrageStrategy:
    """
    Statistical Arbitrage Strategy

    Exploits price inefficiencies between correlated instruments.
    Uses pairs trading and cointegration.

    Optimized for:
    - Multi-instrument analysis
    - Fast correlation calculations
    - FPGA-accelerated math
    """

    def __init__(self,
                 correlation_threshold: float = 0.8,
                 spread_z_threshold: float = 2.0,
                 lookback_periods: int = 100):
        """
        Initialize statistical arbitrage strategy

        Args:
            correlation_threshold: Minimum correlation for pairs
            spread_z_threshold: Z-score threshold for entry
            lookback_periods: Historical periods for analysis
        """
        self.correlation_threshold = correlation_threshold
        self.spread_z_threshold = spread_z_threshold
        self.lookback_periods = lookback_periods

    def generate_signal(self,
                       market_data: MarketData,
                       reference_price: float,
                       spread_history: Optional[List[float]] = None) -> TradingSignal:
        """
        Generate arbitrage signal

        Args:
            market_data: Current market data
            reference_price: Reference instrument price
            spread_history: Historical spread values

        Returns:
            Trading signal
        """
        current_price = market_data.last_price
        spread = current_price - reference_price

        if spread_history is None or len(spread_history) < self.lookback_periods:
            return self._hold_signal(current_price, "Insufficient spread history")

        # Calculate spread statistics
        spreads = np.array(spread_history[-self.lookback_periods:])
        mean_spread = np.mean(spreads)
        std_spread = np.std(spreads)

        if std_spread == 0:
            return self._hold_signal(current_price, "Zero spread volatility")

        # Calculate z-score of current spread
        z_score = (spread - mean_spread) / std_spread

        # Generate signal
        if z_score > self.spread_z_threshold:
            # Current asset overpriced relative to reference
            signal = SignalType.SELL
            entry = current_price
            exit = reference_price + mean_spread
            confidence = min(95.0, abs(z_score) * 30)

        elif z_score < -self.spread_z_threshold:
            # Current asset underpriced relative to reference
            signal = SignalType.BUY
            entry = current_price
            exit = reference_price + mean_spread
            confidence = min(95.0, abs(z_score) * 30)

        else:
            return self._hold_signal(current_price, f"Spread z-score {z_score:.2f} within threshold")

        # Position sizing
        quantity = 1000

        expected_profit = abs(exit - entry) * quantity
        risk_amount = 2 * std_spread * quantity

        return TradingSignal(
            signal=signal,
            entry_price=entry,
            exit_price=exit,
            quantity=quantity,
            confidence=confidence,
            expected_profit=expected_profit,
            risk_amount=risk_amount,
            stop_loss=entry - 3*std_spread if signal == SignalType.BUY else entry + 3*std_spread,
            take_profit=exit,
            reasoning=f"Arbitrage: spread z-score={z_score:.2f}, spread=${spread:.2f}"
        )

    def _hold_signal(self, price: float, reason: str) -> TradingSignal:
        """Generate hold signal"""
        return TradingSignal(
            signal=SignalType.HOLD,
            entry_price=price,
            exit_price=price,
            quantity=0,
            confidence=0.0,
            expected_profit=0.0,
            risk_amount=0.0,
            stop_loss=price,
            take_profit=price,
            reasoning=reason
        )


# Example usage
if __name__ == "__main__":
    print("HFT Trading Strategies - Multi-Base Optimized")
    print("=" * 70)

    # Create sample market data
    market_data = MarketData(
        timestamp=1234567890.0,
        bid_price=100.25,
        ask_price=100.28,
        last_price=100.26,
        bid_size=1000,
        ask_size=1200,
        volume=50000
    )

    # Test each strategy
    print("\n1. Market Making Strategy")
    print("-" * 70)
    mm_strategy = MarketMakingStrategy(min_spread_bps=5.0, max_position=10000)
    signal = mm_strategy.generate_signal(market_data)
    print(f"Signal: {signal.signal.name}")
    print(f"Entry: ${signal.entry_price:.4f}, Exit: ${signal.exit_price:.4f}")
    print(f"Quantity: {signal.quantity}, Confidence: {signal.confidence:.1f}%")
    print(f"Expected Profit: ${signal.expected_profit:.2f}")
    print(f"Reasoning: {signal.reasoning}")

    print("\n2. Mean Reversion Strategy")
    print("-" * 70)
    mr_strategy = MeanReversionStrategy(lookback_periods=20, entry_z_score=2.0)
    # Generate synthetic price history
    price_history = [100.0 + np.sin(i/10) * 2 + np.random.randn() * 0.1 for i in range(25)]
    price_history[-1] = 105.0  # Create large deviation
    signal = mr_strategy.generate_signal(market_data, price_history)
    print(f"Signal: {signal.signal.name}")
    print(f"Entry: ${signal.entry_price:.4f}, Exit: ${signal.exit_price:.4f}")
    print(f"Quantity: {signal.quantity}, Confidence: {signal.confidence:.1f}%")
    print(f"Expected Profit: ${signal.expected_profit:.2f}")
    print(f"Reasoning: {signal.reasoning}")

    print("\n3. Momentum Strategy")
    print("-" * 70)
    mom_strategy = MomentumStrategy(fast_period=8, slow_period=16)
    # Generate trending price history
    price_history = [100.0 + i * 0.1 + np.random.randn() * 0.05 for i in range(20)]
    signal = mom_strategy.generate_signal(market_data, price_history)
    print(f"Signal: {signal.signal.name}")
    print(f"Entry: ${signal.entry_price:.4f}, Exit: ${signal.exit_price:.4f}")
    print(f"Quantity: {signal.quantity}, Confidence: {signal.confidence:.1f}%")
    print(f"Expected Profit: ${signal.expected_profit:.2f}")
    print(f"Reasoning: {signal.reasoning}")

    print("\n4. Statistical Arbitrage Strategy")
    print("-" * 70)
    arb_strategy = StatisticalArbitrageStrategy(spread_z_threshold=2.0)
    spread_history = [0.5 + np.random.randn() * 0.1 for _ in range(100)]
    spread_history[-1] = 1.5  # Create arbitrage opportunity
    signal = arb_strategy.generate_signal(market_data, reference_price=99.0, spread_history=spread_history)
    print(f"Signal: {signal.signal.name}")
    print(f"Entry: ${signal.entry_price:.4f}, Exit: ${signal.exit_price:.4f}")
    print(f"Quantity: {signal.quantity}, Confidence: {signal.confidence:.1f}%")
    print(f"Expected Profit: ${signal.expected_profit:.2f}")
    print(f"Reasoning: {signal.reasoning}")

    print("\n" + "=" * 70)
