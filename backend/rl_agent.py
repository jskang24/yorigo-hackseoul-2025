"""
Reinforcement Learning Agent using Q-Learning Algorithm
for Personalized Recipe Recommendations

This module implements a Q-learning agent that learns optimal recommendation strategies
by exploring different recipe recommendations and learning from user feedback.
"""

import json
import os
import hashlib
from typing import Dict, List, Optional, Tuple, Any
from datetime import datetime
import random
import numpy as np


class QLearningAgent:
    """
    Q-Learning Agent for recipe recommendations.
    
    State Space: Combination of:
    - Cart ingredients (main ingredients hash)
    - User preferences (tags, categories hash)
    - Available recipes count
    
    Action Space: Recipe IDs to recommend
    
    Reward:
    - +1.0 for positive feedback (user adds to cart)
    - -0.5 for negative feedback (user ignores)
    - -0.1 for timeout (no feedback after some time)
    """
    
    def __init__(
        self,
        learning_rate: float = 0.1,
        discount_factor: float = 0.95,
        epsilon: float = 0.1,
        epsilon_decay: float = 0.995,
        epsilon_min: float = 0.01,
        q_table_file: str = "q_table.json"
    ):
        """
        Initialize Q-Learning Agent.
        
        Args:
            learning_rate: How much to update Q-values (alpha)
            discount_factor: Importance of future rewards (gamma)
            epsilon: Exploration rate (probability of random action)
            epsilon_decay: Rate at which epsilon decreases
            epsilon_min: Minimum epsilon value
            q_table_file: File to store Q-table
        """
        self.learning_rate = learning_rate
        self.discount_factor = discount_factor
        self.epsilon = epsilon
        self.epsilon_decay = epsilon_decay
        self.epsilon_min = epsilon_min
        self.q_table_file = q_table_file
        
        # Q-table: {state_hash: {action_id: q_value}}
        self.q_table: Dict[str, Dict[str, float]] = {}
        
        # Track state-action pairs for learning
        self.state_action_history: List[Tuple[str, str, float, Optional[str]]] = []
        
        # Load existing Q-table
        self._load_q_table()
    
    def _load_q_table(self):
        """Load Q-table from file."""
        if os.path.exists(self.q_table_file):
            try:
                with open(self.q_table_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    self.q_table = data.get('q_table', {})
                    self.epsilon = data.get('epsilon', self.epsilon)
                    print(f"[RL] Loaded Q-table with {len(self.q_table)} states")
            except Exception as e:
                print(f"[RL] Failed to load Q-table: {e}")
                self.q_table = {}
        else:
            self.q_table = {}
    
    def _save_q_table(self):
        """Save Q-table to file."""
        try:
            data = {
                'q_table': self.q_table,
                'epsilon': self.epsilon,
                'last_updated': datetime.now().isoformat()
            }
            with open(self.q_table_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"[RL] Failed to save Q-table: {e}")
    
    def hash_state(
        self,
        cart_ingredients: List[str],
        user_preferences: Dict[str, Any],
        available_recipes_count: int
    ) -> str:
        """
        Create a hash representation of the state.
        
        Args:
            cart_ingredients: List of main ingredients in cart
            user_preferences: User's taste preferences
            available_recipes_count: Number of available recipes
        
        Returns:
            State hash string
        """
        # Normalize and sort ingredients
        ingredients_str = '|'.join(sorted([ing.lower().strip() for ing in cart_ingredients]))
        
        # Hash preferences
        tags = sorted(user_preferences.get('tags', []))
        categories = user_preferences.get('categories', {})
        pref_str = f"{tags}|{categories.get('cuisine_type', [])}|{categories.get('meal_time', [])}"
        
        # Create state representation
        state_str = f"{ingredients_str}||{pref_str}||{available_recipes_count}"
        
        # Hash to fixed length
        return hashlib.md5(state_str.encode('utf-8')).hexdigest()
    
    def _get_q_value(self, state: str, action: str) -> float:
        """Get Q-value for state-action pair."""
        return self.q_table.get(state, {}).get(action, 0.0)
    
    def _set_q_value(self, state: str, action: str, value: float):
        """Set Q-value for state-action pair."""
        if state not in self.q_table:
            self.q_table[state] = {}
        self.q_table[state][action] = value
    
    def _get_max_q_value(self, state: str, available_actions: List[str]) -> float:
        """Get maximum Q-value for a state given available actions."""
        if not available_actions:
            return 0.0
        
        max_q = float('-inf')
        for action in available_actions:
            q_value = self._get_q_value(state, action)
            max_q = max(max_q, q_value)
        
        return max_q if max_q != float('-inf') else 0.0
    
    def _get_best_action(self, state: str, available_actions: List[str]) -> Optional[str]:
        """Get best action (highest Q-value) for a state."""
        if not available_actions:
            return None
        
        best_action = None
        best_q = float('-inf')
        
        for action in available_actions:
            q_value = self._get_q_value(state, action)
            if q_value > best_q:
                best_q = q_value
                best_action = action
        
        return best_action if best_action else available_actions[0]
    
    def select_action(
        self,
        state: str,
        available_actions: List[str],
        use_epsilon: bool = True
    ) -> Optional[str]:
        """
        Select action using epsilon-greedy policy.
        
        Args:
            state: Current state hash
            available_actions: List of available recipe IDs
            use_epsilon: Whether to use epsilon-greedy (True) or greedy (False)
        
        Returns:
            Selected recipe ID (action)
        """
        if not available_actions:
            return None
        
        # Epsilon-greedy: explore with probability epsilon, exploit otherwise
        if use_epsilon and random.random() < self.epsilon:
            # Explore: random action
            return random.choice(available_actions)
        else:
            # Exploit: best action based on Q-values
            return self._get_best_action(state, available_actions)
    
    def update_q_value(
        self,
        state: str,
        action: str,
        reward: float,
        next_state: Optional[str] = None,
        next_available_actions: Optional[List[str]] = None
    ):
        """
        Update Q-value using Q-learning update rule (Bellman equation).
        
        Q(s, a) = Q(s, a) + alpha * [r + gamma * max(Q(s', a')) - Q(s, a)]
        
        Args:
            state: Current state
            action: Action taken
            reward: Reward received
            next_state: Next state (if available)
            next_available_actions: Available actions in next state
        """
        current_q = self._get_q_value(state, action)
        
        # Calculate max Q-value for next state
        if next_state and next_available_actions:
            max_next_q = self._get_max_q_value(next_state, next_available_actions)
        else:
            max_next_q = 0.0
        
        # Q-learning update
        new_q = current_q + self.learning_rate * (
            reward + self.discount_factor * max_next_q - current_q
        )
        
        self._set_q_value(state, action, new_q)
        
        # Decay epsilon
        if self.epsilon > self.epsilon_min:
            self.epsilon *= self.epsilon_decay
    
    def learn_from_feedback(
        self,
        state: str,
        action: str,
        feedback: str,
        next_state: Optional[str] = None,
        next_available_actions: Optional[List[str]] = None
    ):
        """
        Learn from user feedback.
        
        Args:
            state: State when recommendation was made
            action: Recipe ID that was recommended
            feedback: "positive" or "negative"
            next_state: Next state (if available)
            next_available_actions: Available actions in next state
        """
        # Map feedback to reward
        reward = 1.0 if feedback == "positive" else -0.5
        
        # Update Q-value
        self.update_q_value(state, action, reward, next_state, next_available_actions)
        
        # Save Q-table periodically
        self._save_q_table()
        
        print(f"[RL] Updated Q-value: state={state[:8]}..., action={action}, reward={reward}, new_q={self._get_q_value(state, action):.3f}")
    
    def get_state_value(self, state: str, available_actions: List[str]) -> float:
        """Get state value (max Q-value for the state)."""
        return self._get_max_q_value(state, available_actions)
    
    def get_policy(self, state: str, available_actions: List[str]) -> Dict[str, float]:
        """
        Get policy (action probabilities) for a state.
        Uses softmax over Q-values.
        
        Args:
            state: Current state
            available_actions: Available actions
        
        Returns:
            Dictionary mapping action IDs to probabilities
        """
        if not available_actions:
            return {}
        
        # Get Q-values for all actions
        q_values = {action: self._get_q_value(state, action) for action in available_actions}
        
        # Apply softmax
        max_q = max(q_values.values()) if q_values.values() else 0.0
        exp_q = {action: np.exp((q - max_q) / 0.1) for action, q in q_values.items()}
        total = sum(exp_q.values())
        
        if total == 0:
            # Uniform distribution if all Q-values are same
            return {action: 1.0 / len(available_actions) for action in available_actions}
        
        return {action: exp_q[action] / total for action in available_actions}
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get agent statistics."""
        total_states = len(self.q_table)
        total_actions = sum(len(actions) for actions in self.q_table.values())
        
        # Calculate average Q-value
        all_q_values = []
        for state_actions in self.q_table.values():
            all_q_values.extend(state_actions.values())
        avg_q = np.mean(all_q_values) if all_q_values else 0.0
        
        return {
            'total_states': total_states,
            'total_state_action_pairs': total_actions,
            'average_q_value': float(avg_q),
            'epsilon': self.epsilon,
            'learning_rate': self.learning_rate,
            'discount_factor': self.discount_factor
        }


class PersonalizedQLearningAgent:
    """
    Per-user Q-Learning Agent wrapper.
    Maintains separate Q-tables for each user for personalized learning.
    """
    
    def __init__(self, base_agent: QLearningAgent):
        """
        Initialize personalized agent.
        
        Args:
            base_agent: Base Q-learning agent to use as template
        """
        self.base_agent = base_agent
        self.user_agents: Dict[str, QLearningAgent] = {}
    
    def get_user_agent(self, user_id: str) -> QLearningAgent:
        """Get or create Q-learning agent for a user."""
        if user_id not in self.user_agents:
            # Create new agent for user with same parameters as base
            self.user_agents[user_id] = QLearningAgent(
                learning_rate=self.base_agent.learning_rate,
                discount_factor=self.base_agent.discount_factor,
                epsilon=self.base_agent.epsilon,
                epsilon_decay=self.base_agent.epsilon_decay,
                epsilon_min=self.base_agent.epsilon_min,
                q_table_file=f"q_table_{user_id}.json"
            )
        return self.user_agents[user_id]
    
    def select_action_for_user(
        self,
        user_id: str,
        state: str,
        available_actions: List[str],
        use_epsilon: bool = True
    ) -> Optional[str]:
        """Select action for a specific user."""
        agent = self.get_user_agent(user_id)
        return agent.select_action(state, available_actions, use_epsilon)
    
    def learn_from_feedback_for_user(
        self,
        user_id: str,
        state: str,
        action: str,
        feedback: str,
        next_state: Optional[str] = None,
        next_available_actions: Optional[List[str]] = None
    ):
        """Learn from feedback for a specific user."""
        agent = self.get_user_agent(user_id)
        agent.learn_from_feedback(state, action, feedback, next_state, next_available_actions)
    
    def get_user_statistics(self, user_id: str) -> Dict[str, Any]:
        """Get statistics for a specific user's agent."""
        agent = self.get_user_agent(user_id)
        return agent.get_statistics()

