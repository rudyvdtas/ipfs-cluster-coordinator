export type Project = {
  id: string;
  name: string;
  description: string;
  cidFilter?: (cid: string) => boolean;
};

// All active projects. CIDs are matched by CID prefix or custom filter.
// Currently all curated CIDs belong to the CyberWatch_TheGuild project.
// Add new projects here and they will appear as a tab on the Projects page.
export const projects: Project[] = [
  {
    id: 'cyberwatch',
    name: 'CyberWatch · TheGuild',
    description: 'Curated CyberWatch content — 110 CIDs distributed across the cluster',
  }
];

export function getProject(id: string): Project | undefined {
  return projects.find((p) => p.id === id);
}