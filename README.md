# TheyChat! - A Reliable Distributed Chat System

TheyChat! is a fault-tolerant, distributed chat system implemented in Erlang. It demonstrates the use of Erlang's process management and message passing features to create a reliable client-server messaging architecture.

## Architecture

The system consists of three main components:

1. **Client Node**
   - Handles joining/leaving servers
   - Manages sending and receiving messages
   - Can connect to multiple chat servers

2. **Router Node**
   - Maintains a registry of available servers
   - Provides server information to clients
   - Supervises server nodes for fault tolerance

3. **Server Node**
   - Manages chat rooms and message distribution
   - Implements fail-safe features
   - Monitors client connections
   - Maintains recoverable state

## Features

- Distributed architecture using separate Erlang Virtual Machines
- Fault tolerance with automatic failure detection
- State persistence for recovery after failures
- Automatic client disconnection detection
- Inter-process communication across different VMs
- Supervisor/worker pattern implementation
