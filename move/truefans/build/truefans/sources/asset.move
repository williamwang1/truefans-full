module truefans::asset {
    use sui::object::{Self, ID, UID};

    struct Well has key, store{
        id: UID
    }
}