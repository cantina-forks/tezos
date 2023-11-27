meta:
  id: id_005__psbabym1__delegate__balance_updates
  endian: be
doc: ! 'Encoding id: 005-PsBabyM1.delegate.balance_updates'
types:
  deposits:
    seq:
    - id: delegate
      type: public_key_hash
    - id: cycle
      type: s4
  fees:
    seq:
    - id: delegate
      type: public_key_hash
    - id: cycle
      type: s4
  id_005__psbabym1__contract_id:
    doc: ! >-
      A contract handle: A contract notation as given to an RPC or inside scripts.
      Can be a base58 implicit contract hash or a base58 originated contract hash.
    seq:
    - id: id_005__psbabym1__contract_id_tag
      type: u1
      enum: id_005__psbabym1__contract_id_tag
    - id: implicit
      type: public_key_hash
      if: (id_005__psbabym1__contract_id_tag == id_005__psbabym1__contract_id_tag::implicit)
    - id: originated
      type: originated
      if: (id_005__psbabym1__contract_id_tag == id_005__psbabym1__contract_id_tag::originated)
  id_005__psbabym1__operation_metadata__alpha__balance:
    seq:
    - id: id_005__psbabym1__operation_metadata__alpha__balance_tag
      type: u1
      enum: id_005__psbabym1__operation_metadata__alpha__balance_tag
    - id: contract
      type: id_005__psbabym1__contract_id
      if: (id_005__psbabym1__operation_metadata__alpha__balance_tag == id_005__psbabym1__operation_metadata__alpha__balance_tag::contract)
    - id: rewards
      type: rewards
      if: (id_005__psbabym1__operation_metadata__alpha__balance_tag == id_005__psbabym1__operation_metadata__alpha__balance_tag::rewards)
    - id: fees
      type: fees
      if: (id_005__psbabym1__operation_metadata__alpha__balance_tag == id_005__psbabym1__operation_metadata__alpha__balance_tag::fees)
    - id: deposits
      type: deposits
      if: (id_005__psbabym1__operation_metadata__alpha__balance_tag == id_005__psbabym1__operation_metadata__alpha__balance_tag::deposits)
  id_005__psbabym1__operation_metadata__alpha__balance_updates:
    seq:
    - id: len_id_005__psbabym1__operation_metadata__alpha__balance_updates
      type: s4
    - id: id_005__psbabym1__operation_metadata__alpha__balance_updates
      type: id_005__psbabym1__operation_metadata__alpha__balance_updates_entries
      size: len_id_005__psbabym1__operation_metadata__alpha__balance_updates
      repeat: eos
  id_005__psbabym1__operation_metadata__alpha__balance_updates_entries:
    seq:
    - id: id_005__psbabym1__operation_metadata__alpha__balance
      type: id_005__psbabym1__operation_metadata__alpha__balance
    - id: change
      type: s8
  originated:
    seq:
    - id: contract_hash
      size: 20
    - id: originated_padding
      size: 1
      doc: This field is for padding, ignore
  public_key_hash:
    doc: A Ed25519, Secp256k1, or P256 public key hash
    seq:
    - id: public_key_hash_tag
      type: u1
      enum: public_key_hash_tag
    - id: ed25519
      size: 20
      if: (public_key_hash_tag == public_key_hash_tag::ed25519)
    - id: secp256k1
      size: 20
      if: (public_key_hash_tag == public_key_hash_tag::secp256k1)
    - id: p256
      size: 20
      if: (public_key_hash_tag == public_key_hash_tag::p256)
  rewards:
    seq:
    - id: delegate
      type: public_key_hash
    - id: cycle
      type: s4
enums:
  id_005__psbabym1__contract_id_tag:
    0: implicit
    1: originated
  id_005__psbabym1__operation_metadata__alpha__balance_tag:
    0: contract
    1: rewards
    2: fees
    3: deposits
  public_key_hash_tag:
    0: ed25519
    1: secp256k1
    2: p256
seq:
- id: id_005__psbabym1__operation_metadata__alpha__balance_updates
  type: id_005__psbabym1__operation_metadata__alpha__balance_updates
