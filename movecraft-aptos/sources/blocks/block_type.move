module movecraft::block_type {

    use movecraft::log;
    use movecraft::planks;
    
    const ENOT_VALID_BLOCK_TYPE: u64 = 2;
    
    public fun name(block_type_index: u64): vector<u8>{
        if(block_type_index == log::block_type()){
            log::name()
        }else if(block_type_index == planks::block_type()){
            planks::name()
        }else{
            abort ENOT_VALID_BLOCK_TYPE
        }
    }
    
    public fun description(block_type_index: u64): vector<u8>{
        if(block_type_index == log::block_type()){
            log::description()
        }else if(block_type_index == planks::block_type()){
            planks::description()
        }else{
            abort ENOT_VALID_BLOCK_TYPE
        }
    }
    
    public fun uri(block_type_index: u64): vector<u8>{
        if(block_type_index == log::block_type()){
            log::uri()
        }else if(block_type_index == planks::block_type()){
            planks::uri()
        }else{
            abort ENOT_VALID_BLOCK_TYPE
        }
    }

    public fun is_mintable(block_type_index: u64): bool{
        if(block_type_index == log::block_type()){
            log::mintable()
        }else if(block_type_index == planks::block_type()){
            planks::mintable()
        }else{
            abort ENOT_VALID_BLOCK_TYPE
        }
    }

    public fun is_stackable(block_type_index: u64): bool{
        if(block_type_index == log::block_type()){
            log::stackable()
        }else if(block_type_index == planks::block_type()){
            planks::stackable()
        }else{
            abort ENOT_VALID_BLOCK_TYPE
        }
    }

}