"""
HFT Trading Strategies Package
"""

from .hft_strategies import (
    SignalType,
    StrategyType,
    MarketData,
    TradingSignal,
    MarketMakingStrategy,
    MeanReversionStrategy,
    MomentumStrategy,
    StatisticalArbitrageStrategy
)

__all__ = [
    'SignalType',
    'StrategyType',
    'MarketData',
    'TradingSignal',
    'MarketMakingStrategy',
    'MeanReversionStrategy',
    'MomentumStrategy',
    'StatisticalArbitrageStrategy'
]

__version__ = '1.0.0'
