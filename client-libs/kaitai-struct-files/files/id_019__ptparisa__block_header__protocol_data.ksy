meta:
  id: id_019__ptparisa__block_header__protocol_data
  endian: be
doc: ! 'Encoding id: 019-PtParisA.block_header.protocol_data'
types:
  id_019__ptparisa__block_header__alpha__signed_contents:
    seq:
    - id: id_019__ptparisa__block_header__alpha__unsigned_contents
      type: id_019__ptparisa__block_header__alpha__unsigned_contents
    - id: signature
      size-eos: true
  id_019__ptparisa__block_header__alpha__unsigned_contents:
    seq:
    - id: payload_hash
      size: 32
    - id: payload_round
      type: s4be
    - id: proof_of_work_nonce
      size: 8
    - id: seed_nonce_hash_tag
      type: u1
      enum: bool
    - id: seed_nonce_hash
      size: 32
      if: (seed_nonce_hash_tag == bool::true)
    - id: per_block_votes
      type: id_019__ptparisa__per_block_votes
  id_019__ptparisa__per_block_votes:
    seq:
    - id: id_019__ptparisa__per_block_votes_tag
      type: u1
      enum: id_019__ptparisa__per_block_votes_tag
enums:
  bool:
    0: false
    255: true
  id_019__ptparisa__per_block_votes_tag:
    0: case_0
    1: case_1
    2: case_2
    4: case_4
    5: case_5
    6: case_6
    8: case_8
    9: case_9
    10: case_10
seq:
- id: id_019__ptparisa__block_header__alpha__signed_contents
  type: id_019__ptparisa__block_header__alpha__signed_contents
