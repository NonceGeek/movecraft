module movecraft::block {
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::event;
    use aptos_framework::object;
    use aptos_framework::timestamp;
    use aptos_std::string_utils::{Self, to_string};
    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_token_objects::collection;
    use aptos_token_objects::token;
    use std::option;
    use std::signer::address_of;
    use std::signer;
    use std::string::{Self, String};

    use movecraft::block_type;

    /// Movecraft error codes
    const ENOT_SIGNER_NOT_ADMIN: u64 = 1;
    const ENOT_VALID_BLOCK_TYPE: u64 = 2;
    const ENOT_BLOCK_OWNER: u64 = 3;
    const ENOT_VALID_BLOCK: u64 = 4;
    const ENOT_STACKABLE: u64 = 5;

    /// Movecraft constants
    const STATE_SEED: vector<u8> = b"movecraft_signer";
    const MINT_SEED: vector<u8> = b"mint_signer";
    const BURN_SEED: vector<u8> = b"burn_signer";

    const BLOCK_COLLECTION_NAME: vector<u8> = b"Block";
    const BLOCK_COLLECTION_DESCRIPTION: vector<u8> = b"Movecraft Block";
    const BLOCK_COLLECTION_URI: vector<u8> = b"block.png";

    const LOG_BLOCK_TYPE: u64 = 11;
    const PLANK_BLOCK_TYPE: u64 = 12;

    /// Global state
    struct State has key {
        // the signer cap of the module's resource account
        signer_cap: SignerCapability, 
        
        last_block_id: u64,

        // block address collection
        blocks: SimpleMap<u64, address>,

        // events
        mint_block_events: event::EventHandle<MintBlockEvents>,
        burn_block_events: event::EventHandle<BurnBlockEvents>,
        stack_block_events: event::EventHandle<StackBlockEvents>,
    }

    struct Block has key {
        name: String,
        type: u64,
        stackable: bool,
        count: u64,
        mutator_ref: token::MutatorRef,
        burn_ref: token::BurnRef,        
    }
    
    // Movecraft events
    struct MintBlockEvents has drop, store {
        name: String,
        block_id: u64,
        creator: address,
        event_timestamp: u64
    }

    struct BurnBlockEvents has drop, store {
        name: String,
        block_id: u64,
        owner: address,
        event_timestamp: u64
    }

    struct StackBlockEvents has drop, store {
        block_id: u64,
        other_block_id: u64,
        owner: address,
        event_timestamp: u64
    }

    // This function is only callable during publishing
    fun init_module(admin: &signer) {
        // Validate signer is admin
        assert!(signer::address_of(admin) == @movecraft, ENOT_SIGNER_NOT_ADMIN);

        // Create the resource account with admin account and provided SEED constant
        let (resource_account, signer_cap) = account::create_resource_account(admin, STATE_SEED);

        move_to(&resource_account, State {
            signer_cap,
            last_block_id: 0,
            blocks: simple_map::create(),
            mint_block_events: account::new_event_handle<MintBlockEvents>(&resource_account),
            burn_block_events: account::new_event_handle<BurnBlockEvents>(&resource_account),
            stack_block_events: account::new_event_handle<StackBlockEvents>(&resource_account),
        });

        // Create log and planks collection to the resource account
        collection::create_unlimited_collection(
            &resource_account,
            string::utf8(BLOCK_COLLECTION_DESCRIPTION),
            string::utf8(BLOCK_COLLECTION_NAME),
            option::none(),
            string::utf8(BLOCK_COLLECTION_URI),
        );
    }

    // Mint block by type
    fun mint_by_type(creator: &signer, type: u64) acquires State {
        
        let block_type_name = string::utf8(block_type::name(type));

        let resource_address = get_resource_address();
        let state = borrow_global_mut<State>(resource_address);
        let resource_account = account::create_signer_with_capability(&state.signer_cap);

        let block_id = state.last_block_id + 1;
        let token_name = string_utils::format2(&b"{} #{}", block_type_name, block_id);

        let description = string::utf8(block_type::description(type));
        let uri = string::utf8(block_type::uri(type));

        let constructor_ref = token::create_named_token(
            &resource_account,
            string::utf8(BLOCK_COLLECTION_NAME),
            description,
            token_name,
            option::none(),
            uri,
        );

        // Generate mint, burn, transfer cap
        let token_signer = object::generate_signer(&constructor_ref);
        let mutator_ref = token::generate_mutator_ref(&constructor_ref);
        let burn_ref = token::generate_burn_ref(&constructor_ref);
        let transfer_ref = object::generate_transfer_ref(&constructor_ref);

        // Move block object into token signer
        let block = Block {
            name: token_name,
            type,
            stackable: block_type::is_stackable(type),
            count: 1,
            mutator_ref,
            burn_ref,
        };

        move_to(&token_signer, block);

        // Move token to creator
        let creator_address = address_of(creator);
        object::transfer_with_ref(object::generate_linear_transfer_ref(&transfer_ref), creator_address);

        // Update last block id
        let block_address = signer::address_of(&token_signer);
        simple_map::add(&mut state.blocks, block_id, block_address);
        state.last_block_id = block_id;

        // Emit mint event
        event::emit_event<MintBlockEvents>(
            &mut state.mint_block_events,
            MintBlockEvents {
                name: token_name,
                block_id,
                creator: creator_address,
                event_timestamp: timestamp::now_seconds(),
            },
        );
    }

    // Burn block by owner
    fun burn_block(owner: &signer, block_id: u64) acquires State, Block {
        
        let resource_address = get_resource_address();
        let state = borrow_global_mut<State>(resource_address);

        // Get block address
        let owner_address = signer::address_of(owner);
        let block_address = get_block_address(&state.blocks, owner_address, block_id);

        let block = move_from<Block>(block_address);
        let Block {
            name,
            burn_ref,
            type: _,
            count: _,
            mutator_ref: _,
            stackable: _,
        } = block;

        // Emit burn event
        event::emit_event<BurnBlockEvents>(
            &mut state.burn_block_events,
            BurnBlockEvents {
                name,
                block_id,
                owner: owner_address,
                event_timestamp: timestamp::now_seconds(),
            },
        );

        // Burn token
        token::burn(burn_ref);
        simple_map::remove(&mut state.blocks, &block_id);
    }

    // Stack by owned blocks
    fun stack(owner: &signer, block_1_id: u64, block_2_id: u64) acquires State, Block {
        
        let resource_address = get_resource_address();
        let state = borrow_global_mut<State>(resource_address);
        let owner_address = signer::address_of(owner);

        // Validate block stackable
        let block_2_address = *simple_map::borrow(&state.blocks, &block_2_id);
        let block_2 = borrow_global<Block>(block_2_address);
        assert!(block_2.stackable, ENOT_STACKABLE);
        let other_count = block_2.count;

        let block_1_address = *simple_map::borrow(&state.blocks, &block_1_id);
        let block_1 = borrow_global_mut<Block>(block_1_address);
        assert!(block_1.stackable, ENOT_STACKABLE);

        // Update block count
        block_1.count = block_1.count + other_count;

        // Emit stack event
        event::emit_event<StackBlockEvents>(
            &mut state.stack_block_events,
            StackBlockEvents {
                block_id: block_1_id,
                other_block_id: block_2_id,
                owner: owner_address,
                event_timestamp: timestamp::now_seconds(),
            },
        );

        // Burn block 2
        burn_block(owner, block_2_id);
    }

    /// Helper functions
    fun get_resource_address(): address {
        account::create_resource_address(&@movecraft, STATE_SEED)
    }

    fun get_block_address(blocks: &SimpleMap<u64, address>, owner_address: address, block_id: u64): address {
        assert!(simple_map::contains_key(blocks, &block_id), ENOT_VALID_BLOCK);
        let block_address = *simple_map::borrow(blocks, &block_id);

        let block_token_obj = object::address_to_object<token::Token>(block_address);
        let token_owner_address = object::owner(block_token_obj);
        assert!(owner_address == token_owner_address, ENOT_BLOCK_OWNER);

        block_address
    }

    /// Viewer functions
    #[view]
    public fun get_block(block_id: u64): (String, u64) acquires State, Block {
        let resource_address = get_resource_address();
        let state = borrow_global<State>(resource_address);
        assert!(simple_map::contains_key(&state.blocks, &block_id), ENOT_VALID_BLOCK);
        let block_address = *simple_map::borrow(&state.blocks, &block_id);

        let block = borrow_global<Block>(block_address);
        (block.name, block.count)
    }

    // ==== TESTS ====
    // Setup testing environment
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    use std::string::utf8;

    #[test_only]
    fun setup_test(aptos: &signer, account: &signer, creator: &signer){
        // create a fake account (only for testing purposes)
        create_account_for_test(signer::address_of(creator));
        create_account_for_test(signer::address_of(account));

        timestamp::set_time_has_started_for_testing(aptos);
        init_module(account);
    }

    // Test creating an Log & Planks block
    #[test(aptos = @0x1, account = @movecraft, creator = @0x123)]
    fun test_mint_block(aptos: &signer, account: &signer, creator: &signer) acquires State {
        setup_test(aptos, account, creator);

        mint_by_type(creator, LOG_BLOCK_TYPE);
        mint_by_type(creator, LOG_BLOCK_TYPE);
        mint_by_type(creator, LOG_BLOCK_TYPE);

        mint_by_type(creator, PLANK_BLOCK_TYPE);
        mint_by_type(creator, PLANK_BLOCK_TYPE);
    }

    // Test burn block
    #[test(aptos = @0x1, account = @movecraft, creator = @0x123)]
    fun test_burn_block(aptos: &signer, account: &signer, creator: &signer) acquires State, Block {
        setup_test(aptos, account, creator);

        mint_by_type(creator, LOG_BLOCK_TYPE);
        burn_block(creator, 1);
    }

    // Test burn block failed
    #[test(aptos = @0x1, account = @movecraft, creator = @0x123)]
    #[expected_failure(abort_code = ENOT_VALID_BLOCK, location = Self)]
    fun test_burn_block_failed_invalid_block(aptos: &signer, account: &signer, creator: &signer) acquires State, Block {
        setup_test(aptos, account, creator);

        mint_by_type(creator, LOG_BLOCK_TYPE);
        burn_block(creator, 1);

        // Not able to burn block again
        burn_block(creator, 1);
    }

    // Test burn block failed with other user
    #[test(aptos = @0x1, account = @movecraft, creator = @0x123, user = @0x124)]
    #[expected_failure(abort_code = ENOT_BLOCK_OWNER, location = Self)]
    fun test_burn_block_failed_other_owner(aptos: &signer, account: &signer, creator: &signer, user: &signer) acquires State, Block {
        setup_test(aptos, account, creator);
        create_account_for_test(signer::address_of(user));

        mint_by_type(creator, LOG_BLOCK_TYPE);
        mint_by_type(creator, PLANK_BLOCK_TYPE);

        burn_block(creator, 1);
        burn_block(user, 2);
    }

    // Test stack block
    #[test(aptos = @0x1, account = @movecraft, creator = @0x123)]
    fun test_stack_block(aptos: &signer, account: &signer, creator: &signer) acquires State, Block {
        setup_test(aptos, account, creator);

        mint_by_type(creator, LOG_BLOCK_TYPE);
        mint_by_type(creator, LOG_BLOCK_TYPE);
        stack(creator, 1, 2);

        let (name, count) = get_block(1);
        assert!(count == 2, 101);
    }
}