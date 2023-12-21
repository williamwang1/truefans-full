#[test_only]
module truefans::profile_test {
    use sui::test_scenario as ts;
    use sui::tx_context;
    use sui::test_utils;
    use truefans::profile::{Self, Global, Profile, ProfilePool, PROFILE};
    use sui::transfer;
    use sui::object_table;
    use sui::object::{Self, ID};
    use sui::coin;
    use std::debug;

    const ADMIN: address = @0xAD;
    const ALICE: address = @0xA;
    const PROTOCOL: address = @0xC;

    const MINIMUM_FUND: u64 = 1;

    #[test]
    fun test_create() { 
        let ts = ts::begin(ADMIN);
        {
            ts::next_tx(&mut ts, ADMIN);
            profile::init_for_testing(
                test_utils::create_one_time_witness<PROFILE>(), 
                ts::ctx(&mut ts)
            );
            profile::create_global(ts::ctx(&mut ts));
        };
        {
            ts::next_tx(&mut ts, ADMIN);
            let global: Global = ts::take_shared(&ts);
            //debug::print(&global);
            assert!(ts::has_most_recent_shared<Global>(), 1);
            ts::return_shared<Global>(global);
        };
        {
            ts::next_tx(&mut ts, ALICE);
            let global: Global = ts::take_shared(&ts);
            let coin = coin::mint_for_testing(MINIMUM_FUND, ts::ctx(&mut ts));
            profile::create(
                b"name",
                coin,
                PROTOCOL,
                &mut global,
                ts::ctx(&mut ts)
            );
            ts::return_shared<Global>(global);
        };
        {
            ts::next_tx(&mut ts, ALICE);
            assert!(ts::has_most_recent_for_sender<Profile>(&ts), 1);
            assert!(ts::has_most_recent_shared<ProfilePool>(), 1);
            
        };
        ts::end(ts);
    }
}