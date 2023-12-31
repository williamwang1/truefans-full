module truefans::profile {
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::transfer;
    use sui::package;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext, sender};
    use sui::url::{Self, Url};
    use sui::object_table::{Self, ObjectTable};
    use sui::event;
    use std::debug;

    const PROFILE_EXISTS: u64 = 0;
    const PROFILE_NOT_EXISTS: u64 = 1;
    const NOT_FOLLOWING: u64 = 2;
    const CANNOT_FOLLOW_SELF: u64 = 3;
    const INSUFFICIENT_FUND: u64 = 1;
    const MINIMUM_FUND: u64 = 1;

    const RPOFILE_OWNER_FEE_PERCENT: u64 = 5;
    const PROTOCOL_FEE_PERCENT: u64 = 1;

    struct ProfileCreated has copy, drop {
        id: ID,
        name: String,
        owner: address
    }

    struct ProfilePoolCreated has copy, drop {
        id: ID,
        for: ID,
        name: String,
        owner: address,
        initial_price: u128
    }

    // struct ProfileSummaryCreated has copy, drop {
    //     id: ID,
    //     for: ID,
    //     owner: address,
    //     name: String,
    // }

    struct Profile has key {
        id: UID,
        owner: address,
        name: String,
        bio: Option<String>,
        avatar: Option<Url>,
        no_of_followers: u64,
        no_of_followings: u64,
        followers: ObjectTable<address, Follow>,
        followings: ObjectTable<address, Follow>
        // transactions
        // assets - ft in sui, wish, wish well, ft in other chains, nfts in other chains
    }

    struct ProfileSummary has key, store {
        id: UID,
        for: ID,
        owner: address,
        name: String,
        bio: Option<String>,
        avatar: Option<Url>,
    }

    struct Follow has key, store {
        id: UID,
        owner: address,
        //following_profile: ProfileSummary,
        following: address,
        follower: address,
       // price: u64,
       // timestamp ??
    }


    struct FollowingCreated has copy, drop {
        id: ID,
        owner: address,
        follower: address,
        following: address,
    }

    struct FollowerCreated has copy, drop {
        id: ID,
        owner: address,
        follower: address,
        following: address,
    }

    struct ProfilePool has key {
        id: UID,
        for: ID,
        initial_price: u64,
        price: u64,
        coins: Coin<SUI>,
    }

    struct Global has key, store {
        id: UID,
        owner: address,
        profiles: ObjectTable<address, ProfileSummary>
    }

    struct PROFILE has drop {}

    fun init(otw: PROFILE, ctx: &mut TxContext) {
        // Claim the `Publisher` for the package!
        let publisher = package::claim(otw, ctx);
        transfer::public_transfer(publisher, sender(ctx));
        // create global, make it share object
        let global_profiles = Global{
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            profiles: object_table::new(ctx)
        };
        debug::print(&global_profiles);
        transfer::public_share_object(global_profiles);
        
    }

    public entry fun create(
        name: vector<u8>,
        payment: Coin<SUI>,
        protocol_destination: address,
        global: &mut Global,
        ctx: &mut TxContext
        ) {
        // check payments is enough
        let value = coin::value(&payment);
        assert!(value == MINIMUM_FUND, INSUFFICIENT_FUND);
        transfer::public_transfer(payment, protocol_destination);
        // check whether have profile created
        let exists = object_table::contains(&global.profiles, sender(ctx));
        assert!(!exists, PROFILE_EXISTS);
        // create profile, transfer to sender, add into global
        let id = object::new(ctx);
        let inner_id = object::uid_to_inner(&id);
        let pool_id = object::new(ctx);
        let inner_pool_id = object::uid_to_inner(&pool_id);
        let summary_id = object::new(ctx);
        let inner_summary_id = object::uid_to_inner(&summary_id);

        // create profilepool 
        let pool = ProfilePool{
            id: pool_id,
            for: inner_pool_id,
            initial_price: 0,
            price: 0,
            coins: coin::from_balance(balance::zero(), ctx)
        };
        transfer::share_object(pool);
        event::emit(
            ProfilePoolCreated{
                id: inner_pool_id,
                for: inner_pool_id,
                name: string::utf8(name),
                owner: sender(ctx),
                initial_price: 1
            }
        );
        let profile = Profile{
            id: id,
            owner: sender(ctx),
            name: string::utf8(name),
            bio: option::none(),
            avatar: option::none(),
            no_of_followers: 0,
            no_of_followings: 0,
            followers: object_table::new(ctx),
            followings: object_table::new(ctx),
        };
        transfer::transfer(profile, sender(ctx));
        event::emit(
            ProfileCreated {
                id: inner_id,
                name: string::utf8(name),
                owner: sender(ctx),
            }
        );
        let profileWrapper = ProfileSummary{
            id: summary_id,
            for: inner_summary_id,
            owner: sender(ctx),
            name: string::utf8(name),
            bio: option::none(),
            avatar: option::none(),
        };
        object_table::add(&mut global.profiles, sender(ctx), profileWrapper);
    }

    public entry fun follow(payment: Coin<SUI>, 
        protocol_destination: address,
        global: &mut Global, 
        profile: &mut Profile, 
        my_profile: &mut Profile, 
        pool: &mut ProfilePool, 
        ctx: &mut TxContext) {
        // make sure sender is not owner
        let following_profile_exists = object_table::contains(&global.profiles, profile.owner);
        let follower_profile_exists = object_table::contains(&global.profiles, my_profile.owner);
        assert!(following_profile_exists, PROFILE_NOT_EXISTS);
        assert!(follower_profile_exists, PROFILE_NOT_EXISTS);
        let follower_id = object::new(ctx);
        let following_id = object::new(ctx);
        let inner_following_id = object::uid_to_inner(&following_id);
        let inner_follower_id = object::uid_to_inner(&follower_id);
        assert!(profile.owner != sender(ctx), CANNOT_FOLLOW_SELF);
        let value = coin::value(&payment);

        let current_price = getPrice(profile.no_of_followers);
        let subjectFee = current_price * RPOFILE_OWNER_FEE_PERCENT / 100;
        let protocolFee = current_price * PROTOCOL_FEE_PERCENT / 100;
        assert!(value >= current_price + subjectFee + protocolFee, INSUFFICIENT_FUND);
        //coin::split(&mut payment, current_price, ctx);
        //TODO 
        let price_coin = coin::split(&mut payment, current_price, ctx);
        coin::join(&mut pool.coins, price_coin);
        //transfer::public_transfer(coin::split(&mut payment, current_price, ctx), object::uid_to_address(&pool.id));
        transfer::public_transfer(coin::split(&mut payment, subjectFee, ctx), profile.owner);
        transfer::public_transfer(coin::split(&mut payment, protocolFee, ctx), protocol_destination);
        transfer::public_transfer(payment, tx_context::sender(ctx));

        let _following_summary = object_table::borrow(&global.profiles, profile.owner);
        let follower = Follow {
            id: follower_id,
            owner: my_profile.owner,
            following: profile.owner,
            follower: my_profile.owner,
        };
        event::emit(
            FollowerCreated {
                id: inner_follower_id,
                owner: sender(ctx),
                following: profile.owner,
                follower: my_profile.owner,
            }
        );
        let following = Follow {
            id: following_id,
            owner: my_profile.owner,
            follower: my_profile.owner,
            following: profile.owner,

        };
        event::emit(
            FollowingCreated {
                id: inner_following_id,
                owner: profile.owner,
                following: profile.owner,
                follower: my_profile.owner,
            }
        );
        // update following profile
        object_table::add(&mut profile.followers, sender(ctx), following);
        profile.no_of_followers = profile.no_of_followers + 1;
        // update follower profile
        object_table::add(&mut my_profile.followings, profile.owner, follower);
        my_profile.no_of_followings = my_profile.no_of_followings + 1;
        // update profile pool price
        pool.price = getPrice(profile.no_of_followers);
    }

    public entry fun unfollow(
        global: &Global, 
        protocol_destination: address,
        following_profile: &mut Profile, 
        follower_profile: &mut Profile, 
        pool: &mut ProfilePool, 
        ctx: &mut TxContext) {
            let follower = object_table::contains(&following_profile.followers, follower_profile.owner);
            let following = object_table::contains(&follower_profile.followings, following_profile.owner);
            assert!(follower, NOT_FOLLOWING);
            assert!(following, NOT_FOLLOWING);
            let following_profile_exists = object_table::contains(&global.profiles, following_profile.owner);
            let follower_profile_exists = object_table::contains(&global.profiles, follower_profile.owner);
            assert!(following_profile_exists, PROFILE_NOT_EXISTS);
            assert!(follower_profile_exists, PROFILE_NOT_EXISTS);

            let current_price = getPrice(following_profile.no_of_followers);
            let subjectFee = current_price * RPOFILE_OWNER_FEE_PERCENT / 100;
            let protocolFee = current_price * PROTOCOL_FEE_PERCENT / 100;
            // remove coin from pool
            let revenue_coin = coin::split(&mut pool.coins, current_price -  subjectFee -  protocolFee, ctx);
            let subject_coin = coin::split(&mut pool.coins, subjectFee, ctx);
            let protocol_coin = coin::split(&mut pool.coins, protocolFee, ctx);

            transfer::public_transfer(revenue_coin, sender(ctx));
            transfer::public_transfer(subject_coin, following_profile.owner);
            transfer::public_transfer(protocol_coin, protocol_destination);

            // update following profile
            let followernft = object_table::remove(&mut following_profile.followers, follower_profile.owner);
            let Follow {id: follower_id, owner: _, follower: _, following: _} = followernft;
            object::delete(follower_id);
            following_profile.no_of_followers = following_profile.no_of_followers - 1;
            // update follower profile
            let followingnft = object_table::remove(&mut follower_profile.followings, following_profile.owner);
            let Follow {id: following_id, owner: _, follower: _, following: _} = followingnft;
            object::delete(following_id);
            pool.price = getPrice(following_profile.no_of_followers);
    }


    public fun getPrice(no_of_followers: u64): u64 {
        let price = no_of_followers * no_of_followers * 10 / 16;
        // pool.price = price;
        (price)
    }


    #[test_only]
    public fun init_for_testing(otw: PROFILE, ctx: &mut TxContext) {
        init(otw, ctx);
    }

    #[test_only]
    public fun create_global(ctx: &mut TxContext) {
        let global = Global {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            profiles: object_table::new(ctx)
        };
        transfer::public_share_object(global);
    }
}