module truefans::profile {
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use sui::transfer;
    use sui::package;
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext, sender};
    use sui::url::{Self, Url};
    use sui::object_table::{Self, ObjectTable};
    use sui::event;
    use sui::dynamic_object_field as ofield;

    const PROFILE_EXISTS: u64 = 0;
    const PROFILE_NOT_EXISTS: u64 = 1;
    const NOT_FOLLOWING: u64 = 2;
    const CANNOT_FOLLOW_SELF: u64 = 3;
    const MIN_CARD_COST: u64 = 1;

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

    struct Profile has key, store {
        id: UID,
        owner: address,
        name: String,
        bio: Option<String>,
        avatar: Option<Url>,
        no_of_followers: u256,
        no_of_followings: u256,
        followers: ObjectTable<address, Follow>,
        followings: ObjectTable<address, Follow>
        // transactions
        // assets - ft in sui, wish, wish well, ft in other chains, nfts in other chains
    }

    struct ProfileWrapper has key, store {
        id: UID,
        for: ID,
        owner: address,
        // name: String,
        // bio: Option<String>,
        // avatar: Option<Url>,
        // no_of_followers: u256,
        // no_of_followings: u256,
        // followers: ObjectTable<address, Follow>,
        // followings: ObjectTable<address, Follow>
    }

    struct Follow has key, store {
        id: UID,
        owner: address,
        following: address,
        follower: address,
       // price: u256
    }

    struct FollowingCreated has copy, drop {
        id: ID,
        owner: address,
        following: address,
        follower: address
    }

    struct FollowerCreated has copy, drop {
        id: ID,
        owner: address,
        following: address,
        follower: address
    }

    struct ProfilePool has key {
        id: UID,
        for: ID,
        initial_price: u64,
        price: u256,
    }

    struct Global has key {
        id: UID,
        owner: address,
        profiles: ObjectTable<address, ProfileWrapper>
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
        transfer::share_object(global_profiles);
        // display ???
    }

    

    public entry fun create(
        name: vector<u8>,
        global: &mut Global,
        ctx: &mut TxContext
        ) {
        // check whether have profile created
        let exists = object_table::contains(&mut global.profiles, sender(ctx));
        assert!(!exists, PROFILE_EXISTS);
        // create profile, transfer to sender, add into global
        let id = object::new(ctx);
        let pool_id = object::new(ctx);
        let summary_id = object::new(ctx);
        event::emit(
            ProfileCreated {
                id: object::uid_to_inner(&id),
                name: string::utf8(name),
                owner: sender(ctx),
            }
        );
        // create profilepool
        event::emit(
            ProfilePoolCreated {
                id: object::uid_to_inner(&pool_id),
                for: object::uid_to_inner(&id),
                name: string::utf8(name),
                owner: sender(ctx),
                initial_price: 1
            }
        ); 
        let pool = ProfilePool{
            id: pool_id,
            for: object::uid_to_inner(&id),
            initial_price: 1,
            price: 1
        };
        transfer::share_object(pool);

        let profileWrapper = ProfileWrapper{
            id: summary_id,
            for: object::uid_to_inner(&id),
            owner: sender(ctx),
            // name: string::utf8(name),
            // bio: option::none(),
            // avatar: option::none(),
            // no_of_followers: 0,
            // no_of_followings: 0,
            // followers: object_table::new(ctx),
            // followings: object_table::new(ctx),
        };
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
        object_table::add(&mut global.profiles, sender(ctx), profileWrapper);
        
    }

    public entry fun check_balance() {
        // check balance is eough to pay transaction fee and feature deposit

    }

    public entry fun follow(global: &mut Global, profile: &mut Profile, my_profile: &mut Profile, pool: &mut ProfilePool, ctx: &mut TxContext) {
        // make sure sender is not owner
        let following_profile_exists = object_table::contains(&mut global.profiles, profile.owner);
        let follower_profile_exists = object_table::contains(&mut global.profiles, my_profile.owner);
        assert!(following_profile_exists, PROFILE_NOT_EXISTS);
        assert!(follower_profile_exists, PROFILE_NOT_EXISTS);
        let follower_id = object::new(ctx);
        let following_id = object::new(ctx);
        assert!(profile.owner != sender(ctx), CANNOT_FOLLOW_SELF);

        event::emit(
            FollowingCreated {
                id: object::uid_to_inner(&follower_id),
                owner: sender(ctx),
                following: profile.owner,
                follower: sender(ctx)
            }
        );
        event::emit(
            FollowerCreated {
                id: object::uid_to_inner(&following_id),
                owner: sender(ctx),
                following: profile.owner,
                follower: sender(ctx)
            }
        );
        let follower = Follow {
            id: follower_id,
            owner: sender(ctx),
            following: profile.owner,
            follower: sender(ctx),
        };
        let following = Follow {
            id: following_id,
            owner: sender(ctx),
            following: profile.owner,
            follower: sender(ctx),
        };
        // update following profile
        object_table::add(&mut profile.followers, sender(ctx), follower);
        profile.no_of_followers = profile.no_of_followers + 1;
        // update follower profile
        object_table::add(&mut my_profile.followings, profile.owner, following);
        my_profile.no_of_followings = my_profile.no_of_followings + 1;
        // update profile pool price
        pool.price = getPrice(profile.no_of_followers);
    }

    public entry fun unfollow(global: &mut Global, following_profile: &mut Profile, follower_profile: &mut Profile, pool: &mut ProfilePool, ctx: &mut TxContext) {
        let follower = object_table::contains(&mut following_profile.followers, follower_profile.owner);
        let following = object_table::contains(&mut follower_profile.followings, following_profile.owner);
        assert!(follower, NOT_FOLLOWING);
        assert!(following, NOT_FOLLOWING);
        let following_profile_exists = object_table::contains(&global.profiles, following_profile.owner);
        let follower_profile_exists = object_table::contains(&global.profiles, follower_profile.owner);
        assert!(following_profile_exists, PROFILE_NOT_EXISTS);
        assert!(follower_profile_exists, PROFILE_NOT_EXISTS);
        // update following profile
        let followernft = object_table::remove(&mut following_profile.followers, follower_profile.owner);
        let Follow {id: follower_id, owner: _, follower: _, following: _} = followernft;
        object::delete(follower_id);
        following_profile.no_of_followers = following_profile.no_of_followers - 1;
        // update follower profile
        let followingnft = object_table::remove(&mut follower_profile.followings, following_profile.owner);
        let Follow {id: following_id, owner: _, follower: _, following: _} = followingnft;
        object::delete(following_id);
        _ = getPrice(following_profile.no_of_followers);
    }


    public fun getPrice(no_of_followers: u256): u256 {
        let price = no_of_followers * no_of_followers * 10 / 16;
        // pool.price = price;
        (price)
    }
}