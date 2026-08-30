/** Story filter state shared by the catalog View and its toolbar. */
export const TALE_FILTER_BAR_HEIGHT: number = 88;

@ObservedV2
export class TaleFilterState {
  @Trace query: string = '';
  @Trace letter: string = '';

  @Computed
  get active(): boolean {
    return this.query.trim().length > 0 || this.letter.length > 0;
  }

  setQuery(value: string): void {
    this.query = value;
  }

  setLetter(value: string): void {
    if (this.letter !== value) {
      this.letter = value;
    }
  }

  clear(): void {
    this.query = '';
    this.letter = '';
  }
}
