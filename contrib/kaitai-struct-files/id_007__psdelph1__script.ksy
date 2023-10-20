meta:
  id: id_007__psdelph1__script
  endian: be
types:
  id_007__psdelph1__scripted__contracts:
    types:
      storage:
        seq:
        - id: len_storage
          type: s4
        - id: storage
          size: len_storage
      code:
        seq:
        - id: len_code
          type: s4
        - id: code
          size: len_code
    seq:
    - id: code
      type: code
    - id: storage
      type: storage
  storage:
    seq:
    - id: len_storage
      type: s4
    - id: storage
      size: len_storage
  code:
    seq:
    - id: len_code
      type: s4
    - id: code
      size: len_code
seq:
- id: id_007__psdelph1__scripted__contracts
  type: id_007__psdelph1__scripted__contracts
