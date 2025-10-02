# Intent Reservation Integration Plan

## Goal

Support two flows for creating trade intents:
- Unreserved: anyone can solve the intent after it's created.
- Reserved: only a specific solver (chosen off-chain) can solve the intent.

## Flow Overview

We number the steps in order of execution.
Each numbered item should exactly correspond to the file that implements it.
Then each of these files can have several bullet points of actions.

For example:

0. `some_module.move`
   - Do this
   - Do that

### Stage 1 - Common Path

1. `intent.move`
   - The existing module already defines the core `TradeIntent` struct. We will modify it.
2. `fa_intent.move`
   - Offerer composes the `Intent` data structure that will be passed to the creation function.
3. `intent_reservation.move`
   - Defines the `IntentReserved` struct, containing the `solver` address and their `signature`.
4. `fa_intent.move`
   - Implements a single `create_fa_to_fa_intent_entry` entry function that accepts the `Intent` data and an `Option<IntentReserved>`.
   - This is the single entry point for creating both reserved and unreserved intents.
   - It calls an internal `create_fa_to_fa_intent` function, passing along the reservation option.

### Stage 2 - Two-path part

#### Unreserved Flow Creation

Here we continue the common flow from step 4. Hence we start numbering from 5.

5. `fa_intent.move`
   - To create an unreserved intent, the offerer calls `create_fa_to_fa_intent_entry`, passing `option::none()` for the `reservation` argument.

#### Reserved Flow Creation

Here we continue the common flow from step 4. Hence we start numbering from 5.

5. Off-chain Communication:
   - Offerer shares the `Intent` data with prospective solvers.
   - Solver signs the hash of the intent data and returns the signature to the offerer.
6. `fa_intent.move`
   - Offerer assembles the `IntentReserved` struct (solver address + signature).
   - To create a reserved intent, the offerer calls `create_fa_to_fa_intent_entry`, passing `option::some(IntentReserved)` for the `reservation` argument.

### Stage 3 - Common Path

This phase happens after `create_fa_to_fa_intent_entry` is called. Hence we continue numbering from 7.

7. `intent.move`
   - The internal `create_fa_to_fa_intent` (from `fa_intent.move`) uses the intent data to escrow assets, emits `LimitOrderEvent`, and delegates to `intent::create_intent`.
   - `intent::create_intent` persists the `TradeIntent` object, storing the reservation data if it exists.
8. `fa_intent.move`
   - A solver calls `start_fa_offering_session`, which wraps `intent::start_intent_session`.
   - If the intent is reserved, this function first calls `intent_reservation::ensure_solver_authorized`.
   - Settlement uses `finish_fa_receiving_session`, which validates payment before calling `intent::finish_intent_session`.

## Implementation Tasks

- [ ] **Create `intent_reservation.move`**:
  - [ ] Create the new module file.
  - [ ] Define the `IntentReserved` struct (containing `solver` address and `signature`).
  - [ ] Implement the `ensure_solver_authorized` function for use during settlement.

- [ ] **Update `intent.move`**:
  - [ ] Modify the on-chain `TradeIntent` struct to include a field for `Option<IntentReserved>`, allowing reservation data to be persisted.
  - [ ] Update the `create_intent` function to accept and store the optional reservation data.

- [ ] **Refactor `fa_intent.move`**:
  - [ ] Integrate the reserved flow logic into the existing `create_fa_to_fa_intent_entry` function by adding the `reservation: Option<IntentReserved>` parameter. This is a breaking change to the module's public API.
  - [ ] Update the settlement logic (`start_fa_offering_session`) to call `ensure_solver_authorized` when an intent is reserved.

- [ ] **Update Build Configuration**:
  - [ ] Add the new `intent_reservation` module to the `Move.toml` file to ensure it is included in the project build.
