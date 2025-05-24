####    Image HDU functions

function read(io::IO, ::Type{Image}, format::DataFormat,
    fields::ImageField; scale=true, kwds...)

    begpos = position(io)
    #  Read data array
    M, N = sizeof(format.type), format.leng
    if N > 0
        data = read(io, format, fields)
        #  Seek to end of the last data block
        seek(io, begpos + BLOCKLEN*div(M*N, BLOCKLEN, RoundUp))

        data = scale ? fields.zero .+ fields.scale.*data : data
        #=
        if get(kwds, :unit, true)
            apply_unit(data, cards)
        end
        =#
    else
        data = nothing
    end

    ####    Get WCS keywords
    data
end

function write(io::IO, ::Type{Image}, data::Nothing, format::DataFormat,
    fields::ImageField; kwds...)
end

function write(io::IO, ::Type{Image}, data::AbstractArray,
        format::DataFormat, fields::ImageField; kwds...)
    
    if format.leng > 0
        #  data = remove_units(data)

        write(io, data, fields; kwds...)
        padblock(io, format)
    end
end

function verify!(::Type{Image}, cards::Cards, format::DataFormat,
    mankeys::D) where D<:Dict{AbstractString, ValueType}

    if haskey(mankeys, "BITPIX") && format.type != BITS2TYPE[mankeys["BITPIX"]]
        setindex!(cards, TYPE2BITS[format.type], "BITPIX")
        println("Warning: BITPIX set to $(TYPE2BITS[format.type])).")
    end
    if haskey(mankeys, "NAXIS1") && format.shape != datasize(cards, 1)
        N = length(format.shape)
        setindex!(cards, N, "NAXIS")
        for j=1:N setindex!(cards, format.shape[j], "NAXIS$j") end
        println("Warning: NAXIS$(1:N) set to $(format.shape)")
    end
    cards
end

function DataFormat(::Type{Image}, data::Nothing, mankeys::Dict{S, V}) where
    {S<:AbstractString, V<:ValueType}

    #  Determine format from data
    type  = BITS2TYPE[get(mankeys, "BITPIX", 32)]
    leng  = datalength(mankeys, 1)
    shape = datasize(mankeys, 1)
    param = get(mankeys, "PCOUNT", 0)
    group = get(mankeys, "GCOUNT", 1)
    heap  = param > 0 ? get(mankeys, "THEAP", 0) : 0
    DataFormat(type, leng, shape, param, group, heap)
end

function FieldFormat(::Type{Image}, format::DataFormat, reskeys::Dict{S, V},
    data::Nothing) where {S<:AbstractString, V<:ValueType}

    #  Get missing value
    zero_ = get(reskeys, "BZERO", zero(format.type))
    scale = get(reskeys, "BSCALE", one(format.type))
    miss  = format.type in MISSTYPE ? get(reskeys, "BLANK", nothing) : nothing
    dmin  = get(reskeys, "DATAMIN", nothing)
    dmax  = get(reskeys, "DATAMAX", nothing)
    ImageField(format.type, zero_, scale, miss, dmin, dmax)
end

function DataFormat(::Type{Image}, data::AbstractArray,
    mankeys::Dict{S, V}) where {S<:AbstractString, V<:ValueType}

    #  Determine format from data
    type  = eltype(data)
    leng  = length(data)
    shape = size(data)
    param = get(mankeys, "PCOUNT", 0)
    group = get(mankeys, "GCOUNT", 1)
    heap = 0
    DataFormat(type, leng, shape, param, group, heap)
end

function FieldFormat(::Type{Image}, format::DataFormat, reskeys::Dict{S, V},
    data::AbstractArray) where {S<:AbstractString, V<:ValueType}

    #  Get missing value
    zero_ = get(reskeys, "BZERO", zero(format.type))
    scale = get(reskeys, "BSCALE", one(format.type))
    miss  = format.type in MISSTYPE ? get(reskeys, "BLANK", nothing) : nothing
    dmin  = get(reskeys, "DATAMIN", nothing)
    dmax  = get(reskeys, "DATAMAX", nothing)
    ImageField(format.type, zero_, scale, miss, dmin, dmax)
end

function create_cards!(::Type{Image}, format::DataFormat, fields::ImageField,
    cards::Cards; kwds...)

    N, B = length(format.shape), TYPE2BITS[format.type]
    #  Create mandatory (required) header cards and remove them from the deck
    #  if necessary
    required = Vector{Card{<:Any}}(undef, 3+N)
    required[1] = popat!(cards, "XTENSION", Card("XTENSION", "IMAGE"))
    required[2] = popat!(cards, "BITPIX", Card("BITPIX", B))
    required[3] = popat!(cards, "NAXIS", Card("NAXIS", N))
    required[4:3+N] .= [popat!(cards, "NAXIS$j",
        Card("NAXIS$j", format.shape[j])) for j = 1:N]
    
    #  Append remaining cards in deck, but first remove the END card
    popat!(cards, "END")
    M = length(cards)
    kards = Vector{Card{<:Any}}(undef, 3+N+M)
    kards[1:3+N] .= required
    kards[4+N:3+N+M] .= cards
    #  END card is implied. It will be appended on write.
    kards
end

function create_data(::Type{Image}, format::DataFormat, ::ImageField; kwds...)
    #  Create simple N-dimensional array of zeros of type BITPIX
    length(format.shape) > 0 ? zeros(format.type, format.shape) : nothing
end
