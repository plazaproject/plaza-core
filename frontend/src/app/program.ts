export class ProgramMetadata {
    id: string;
    name: string;
    link: string;
    enabled: boolean;
    type: string;
    bridges_in_use: string[];
}

export type ProgramType = 'scratch_program' | 'flow_program';

export class ProgramContent extends ProgramMetadata {
    type: ProgramType;
    parsed: any;
    orig: any;
    owner: string;

    constructor (metadata: ProgramMetadata, parsed: any, orig: any, type: ProgramType) {
      super();

      this.id = metadata.id;
      this.link = metadata.link;
      this.name = metadata.name;

      this.parsed = parsed;
      this.orig = orig;
      this.type = type;
    }
}

export class ScratchProgram extends ProgramContent {
    constructor(metadata: ProgramMetadata, parsed: any, orig: any) {
       super(metadata, parsed, orig, 'scratch_program');
    }
}

export class FlowProgram extends ProgramContent {
    constructor(metadata: ProgramMetadata, parsed: any, orig: any) {
        super(metadata, parsed, orig, 'scratch_program');
    }
}

export interface ProgramLogEntry {
    program_id: string,
    thread_id: string | 'none',
    user_id: string | 'none',
    block_id: string | undefined,
    severity: 'error' | 'debug' | 'warning',
    event_data: any,
    event_message: string,
    event_time: number,
};

export type ProgramInfoUpdate = { type: "program_log", value: ProgramLogEntry };
